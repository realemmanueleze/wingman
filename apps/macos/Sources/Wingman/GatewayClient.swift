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
    /// Live delta subscribers per runId, so callers can speak/render text
    /// as it streams instead of waiting for the run to finish.
    private var runDeltaHandlers: [String: (String) -> Void] = [:]

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

        // gateway-client + backend + shared token is OpenClaw's device-less
        // loopback trust path: requested scopes are preserved. ui mode clears
        // unbound scopes without device pairing, which yields missing
        // operator.write on agent turns.
        let connectParams: [String: Any] = [
            "minProtocol": 4,
            "maxProtocol": 4,
            "client": [
                "id": "gateway-client",
                "displayName": "Wingman",
                "version": "0.1.0",
                "platform": "darwin",
                "mode": "backend",
                "instanceId": ProcessInfo.processInfo.globallyUniqueString,
            ],
            "role": "operator",
            "scopes": [
                "operator.admin",
                "operator.read",
                "operator.write",
                "operator.approvals",
                "operator.pairing",
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
        imageAttachments: [(data: Data, mimeType: String)],
        thinking: String? = nil,
        onDelta: ((String) -> Void)? = nil
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
        // "off" skips the model's reasoning phase on easy turns for speed.
        if let thinking {
            params["thinking"] = thinking
        }

        // First res is an immediate ack with the runId; the run itself
        // completes asynchronously and a second res (same id) closes it.
        let (ackPayload, requestId) = try await requestKeepingId(
            method: "agent", params: params, timeoutSeconds: 30
        )
        let runId = (ackPayload["runId"] as? String) ?? ""
        if let onDelta {
            // Replay anything that streamed in between the ack and now,
            // then subscribe for live deltas.
            if let alreadyBuffered = runTextBuffers[runId], !alreadyBuffered.isEmpty {
                onDelta(alreadyBuffered)
            }
            runDeltaHandlers[runId] = onDelta
        }
        defer { runDeltaHandlers.removeValue(forKey: runId) }

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

    // MARK: - Sessions browsing

    struct SessionSummary: Identifiable, Equatable {
        let key: String
        let title: String
        let preview: String?
        let updatedAt: Date?
        var id: String { key }
    }

    struct HistoryMessage: Identifiable, Equatable {
        let id = UUID()
        let role: String
        let text: String
    }

    func listSessions(limit: Int = 40) async throws -> [SessionSummary] {
        let payload = try await request(
            method: "sessions.list",
            params: [
                "limit": limit,
                "includeDerivedTitles": true,
                "includeLastMessage": true,
            ]
        )
        let rows = payload["sessions"] as? [[String: Any]] ?? []
        return rows.map { row in
            let key = row["key"] as? String ?? "unknown"
            let title = (row["derivedTitle"] as? String)
                ?? (row["displayName"] as? String)
                ?? (row["label"] as? String)
                ?? key
            let preview = (row["lastMessage"] as? String)
                ?? ((row["lastMessage"] as? [String: Any])?["text"] as? String)
            var updatedAt: Date?
            if let ms = row["updatedAt"] as? Double {
                updatedAt = Date(timeIntervalSince1970: ms / 1000)
            } else if let ms = row["updatedAt"] as? Int {
                updatedAt = Date(timeIntervalSince1970: Double(ms) / 1000)
            }
            return SessionSummary(key: key, title: title, preview: preview, updatedAt: updatedAt)
        }
    }

    func fetchChatHistory(sessionKey: String, limit: Int = 60) async throws -> [HistoryMessage] {
        let payload = try await request(
            method: "chat.history",
            params: ["sessionKey": sessionKey, "limit": limit]
        )
        let rows = payload["messages"] as? [[String: Any]] ?? []
        return rows.compactMap { Self.parseHistoryMessage(row: $0) }
    }

    /// Transcript messages carry content as a string or as typed part arrays;
    /// flatten to displayable text and drop tool/system noise.
    private static func parseHistoryMessage(row: [String: Any]) -> HistoryMessage? {
        let role = row["role"] as? String ?? "assistant"
        guard role == "user" || role == "assistant" else { return nil }

        var text = ""
        if let content = row["content"] as? String {
            text = content
        } else if let parts = row["content"] as? [[String: Any]] {
            text = parts.compactMap { part in
                (part["type"] as? String) == "text" ? part["text"] as? String : nil
            }.joined(separator: "\n")
        } else if let plain = row["text"] as? String {
            text = plain
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HistoryMessage(role: role, text: trimmed)
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
              payload["stream"] as? String == "assistant",
              let eventData = payload["data"] as? [String: Any]
        else { return }
        // Assistant events carry cumulative `text` plus incremental `delta`.
        // Append only deltas; a text-only event is the full reply, so it
        // replaces the buffer. Appending `text` each time duplicates output.
        if let delta = eventData["delta"] as? String, !delta.isEmpty {
            runTextBuffers[runId, default: ""] += delta
            runDeltaHandlers[runId]?(delta)
        } else if let text = eventData["text"] as? String, !text.isEmpty {
            runTextBuffers[runId] = text
        }
    }
}
