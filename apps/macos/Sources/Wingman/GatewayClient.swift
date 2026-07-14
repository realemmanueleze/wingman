import Foundation

/// WebSocket client for the OpenClaw Gateway protocol (v4).
///
/// Speaks the real wire contract from OpenClaw's `packages/gateway-protocol`:
/// first frame is a `connect` request with client info + token auth; then
/// `{type:"req"| "res"|"event"}` envelopes. Agent runs stream back as
/// `agent` events keyed by runId.
@MainActor
final class GatewayClient: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(reason: String)
    }

    @Published private(set) var connectionState: ConnectionState = .disconnected

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var nextRequestId = 1
    private var pendingRequests: [String: CheckedContinuation<[String: Any], Error>] = [:]
    /// Agent runs send TWO responses with the same request id: an immediate
    /// ack ({runId, status:"accepted"}) and a final response when the run
    /// completes. After the ack resolves, the final continuation waits here.
    private var pendingFinalResponses: [String: CheckedContinuation<[String: Any], Error>] = [:]
    /// Collected assistant text per runId, streamed via `agent` events.
    private var runTextBuffers: [String: String] = [:]

    struct GatewayError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func connect(url: URL, token: String) async throws {
        connectionState = .connecting
        let session = URLSession(configuration: .default)
        urlSession = session
        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        receiveLoop()

        let connectParams: [String: Any] = [
            "minProtocol": 4,
            "maxProtocol": 4,
            "client": [
                "id": "gateway-client",
                "displayName": "Wingman",
                "version": "0.1.0",
                "platform": "darwin",
                "mode": "ui",
                "instanceId": ProcessInfo.processInfo.globallyUniqueString,
            ],
            "auth": ["token": token],
        ]
        _ = try await request(method: "connect", params: connectParams)
        connectionState = .connected
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        urlSession = nil
        connectionState = .disconnected
    }

    /// Runs an agent turn and returns the full assistant text once the run
    /// completes. Screen captures ride along as base64 image attachments.
    func runAgentTurn(
        message: String,
        sessionKey: String,
        extraSystemPrompt: String,
        imageAttachments: [(data: Data, mimeType: String)]
    ) async throws -> String {
        let attachments: [[String: Any]] = imageAttachments.map { attachment in
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": attachment.mimeType,
                    "data": attachment.data.base64EncodedString(),
                ],
            ]
        }

        var params: [String: Any] = [
            "message": message,
            "sessionKey": sessionKey,
            "extraSystemPrompt": extraSystemPrompt,
            "deliver": false,
            "idempotencyKey": UUID().uuidString,
        ]
        if !attachments.isEmpty {
            params["attachments"] = attachments
        }

        // First res is an immediate ack with the runId; the run itself
        // completes asynchronously and a second res (same id) closes it.
        let (ackPayload, requestId) = try await requestKeepingId(
            method: "agent", params: params, timeoutSeconds: 30
        )
        let runId = (ackPayload["runId"] as? String) ?? ""

        let finalPayload: [String: Any] = try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.pendingFinalResponses[requestId] = continuation
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 300 * 1_000_000_000)
                throw GatewayError(message: "Agent run timed out after 300s.")
            }
            guard let first = try await group.next() else {
                throw GatewayError(message: "Agent run produced no result.")
            }
            group.cancelAll()
            await MainActor.run { _ = self.pendingFinalResponses.removeValue(forKey: requestId) }
            return first
        }

        let collected = runTextBuffers.removeValue(forKey: runId)
        if let collected, !collected.isEmpty {
            return collected
        }
        if let summary = finalPayload["summary"] as? String, !summary.isEmpty { return summary }
        if let reply = finalPayload["reply"] as? String, !reply.isEmpty { return reply }
        throw GatewayError(message: "Agent run finished without assistant text (runId \(runId)).")
    }

    // MARK: - Wire plumbing

    private func request(
        method: String,
        params: [String: Any],
        timeoutSeconds: Double = 30
    ) async throws -> [String: Any] {
        try await requestKeepingId(method: method, params: params, timeoutSeconds: timeoutSeconds).payload
    }

    private func requestKeepingId(
        method: String,
        params: [String: Any],
        timeoutSeconds: Double
    ) async throws -> (payload: [String: Any], requestId: String) {
        guard let webSocketTask else { throw GatewayError(message: "Not connected.") }

        let requestId = "wingman-\(nextRequestId)"
        nextRequestId += 1

        let frame: [String: Any] = [
            "type": "req",
            "id": requestId,
            "method": method,
            "params": params,
        ]
        let frameData = try JSONSerialization.data(withJSONObject: frame)
        guard let frameText = String(data: frameData, encoding: .utf8) else {
            throw GatewayError(message: "Failed to encode frame.")
        }

        try await webSocketTask.send(.string(frameText))

        let payload = try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.pendingRequests[requestId] = continuation
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw GatewayError(message: "Request \(method) timed out after \(Int(timeoutSeconds))s.")
            }
            guard let first = try await group.next() else {
                throw GatewayError(message: "Request \(method) produced no result.")
            }
            group.cancelAll()
            await MainActor.run { _ = self.pendingRequests.removeValue(forKey: requestId) }
            return first
        }
        return (payload, requestId)
    }

    private func receiveLoop() {
        guard let webSocketTask else { return }
        webSocketTask.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.connectionState = .failed(reason: error.localizedDescription)
                    for (_, continuation) in self.pendingRequests {
                        continuation.resume(throwing: GatewayError(message: "Connection lost."))
                    }
                    self.pendingRequests.removeAll()
                case .success(let message):
                    if case .string(let text) = message {
                        self.handleFrame(text: text)
                    }
                    self.receiveLoop()
                }
            }
        }
    }

    private func handleFrame(text: String) {
        guard let data = text.data(using: .utf8),
              let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frameType = frame["type"] as? String
        else { return }

        switch frameType {
        case "res":
            guard let requestId = frame["id"] as? String else { return }
            // First res for an id resolves the request; a second res with the
            // same id (agent final) resolves the final-response waiter.
            let continuation = pendingRequests.removeValue(forKey: requestId)
                ?? pendingFinalResponses.removeValue(forKey: requestId)
            guard let continuation else { return }
            let ok = frame["ok"] as? Bool ?? false
            if ok {
                continuation.resume(returning: frame["payload"] as? [String: Any] ?? [:])
            } else {
                let errorInfo = frame["error"] as? [String: Any]
                let message = errorInfo?["message"] as? String ?? "Gateway error"
                continuation.resume(throwing: GatewayError(message: message))
            }
        case "event":
            guard let eventName = frame["event"] as? String else { return }
            if eventName == "agent",
               let payload = frame["payload"] as? [String: Any] {
                handleAgentEvent(payload: payload)
            }
        default:
            break
        }
    }

    private func handleAgentEvent(payload: [String: Any]) {
        guard let runId = payload["runId"] as? String,
              let eventData = payload["data"] as? [String: Any]
        else { return }
        // Assistant text deltas arrive in stream data; accumulate per run.
        if let text = eventData["text"] as? String {
            runTextBuffers[runId, default: ""] += text
        } else if let delta = eventData["delta"] as? String {
            runTextBuffers[runId, default: ""] += delta
        }
    }
}
