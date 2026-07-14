import Foundation

/// Supervises the embedded OpenClaw Gateway as a child process so the user
/// double-clicks one app and gets the whole product — no terminal.
///
/// Resolution order for the gateway runtime:
///   1. `WINGMAN_GATEWAY_CMD` env var (development override, e.g.
///      "node /path/to/openclaw/openclaw.mjs gateway")
///   2. Bundled runtime at `<Resources>/gateway/` (node binary + openclaw
///      install staged by scripts/bundle-gateway.sh)
///   3. An already-running gateway on the configured port (attach-only mode:
///      the user runs OpenClaw themselves; Wingman just connects)
///
/// Auth: a per-install token is generated once, written to the app's data
/// directory, exported as OPENCLAW_GATEWAY_TOKEN for the child process, and
/// used by GatewayClient on connect. The gateway binds loopback only.
@MainActor
final class GatewaySidecar: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running(pid: Int32)
        case attachedToExternal
        case failed(reason: String)
    }

    @Published private(set) var state: State = .stopped

    let port: Int
    let host = "127.0.0.1"

    private var process: Process?
    private var restartAttempts = 0
    private let maxRestartAttempts = 3
    private var stopRequested = false

    private static let dataDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wingman", isDirectory: true)
    }()

    init(port: Int = 18789) {
        self.port = port
    }

    /// Loopback auth token shared between the sidecar process and our client.
    /// Generated once per install and persisted with owner-only permissions.
    let authToken: String = {
        let tokenFile = GatewaySidecar.dataDirectory.appendingPathComponent("gateway-token")
        if let existing = try? String(contentsOf: tokenFile, encoding: .utf8),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let token = UUID().uuidString + UUID().uuidString
        try? FileManager.default.createDirectory(
            at: GatewaySidecar.dataDirectory, withIntermediateDirectories: true
        )
        try? token.write(to: tokenFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: tokenFile.path
        )
        return token
    }()

    var webSocketURL: URL { URL(string: "ws://\(host):\(port)")! }

    func start() {
        stopRequested = false
        Task { await startOrAttach() }
    }

    func stop() {
        stopRequested = true
        process?.terminate()
        process = nil
        state = .stopped
    }

    private func startOrAttach() async {
        state = .starting

        // Attach-only: a gateway is already listening (user-managed install).
        if await isPortOpen() {
            state = .attachedToExternal
            return
        }

        guard let command = resolveGatewayCommand() else {
            state = .failed(reason: "No gateway runtime found. Set WINGMAN_GATEWAY_CMD or bundle one with scripts/bundle-gateway.sh, or start OpenClaw yourself.")
            return
        }

        launch(command: command)
    }

    private struct GatewayCommand {
        let executable: URL
        let arguments: [String]
    }

    private func resolveGatewayCommand() -> GatewayCommand? {
        if let override = ProcessInfo.processInfo.environment["WINGMAN_GATEWAY_CMD"],
           !override.isEmpty {
            return GatewayCommand(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", override]
            )
        }

        let bundledNode = Bundle.main.resourceURL?
            .appendingPathComponent("gateway/node/bin/node")
        let bundledEntry = Bundle.main.resourceURL?
            .appendingPathComponent("gateway/openclaw/openclaw.mjs")
        if let bundledNode, let bundledEntry,
           FileManager.default.isExecutableFile(atPath: bundledNode.path),
           FileManager.default.fileExists(atPath: bundledEntry.path) {
            return GatewayCommand(
                executable: bundledNode,
                arguments: [bundledEntry.path, "gateway", "--port", String(port)]
            )
        }

        return nil
    }

    private func launch(command: GatewayCommand) {
        let child = Process()
        child.executableURL = command.executable
        child.arguments = command.arguments

        var environment = ProcessInfo.processInfo.environment
        environment["OPENCLAW_GATEWAY_TOKEN"] = authToken
        child.environment = environment
        child.currentDirectoryURL = Self.dataDirectory

        let logURL = Self.dataDirectory.appendingPathComponent("gateway.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            logHandle.seekToEndOfFile()
            child.standardOutput = logHandle
            child.standardError = logHandle
        }

        child.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                self?.handleTermination(exitCode: finished.terminationStatus)
            }
        }

        do {
            try child.run()
            process = child
            state = .running(pid: child.processIdentifier)
            restartAttempts = 0
        } catch {
            state = .failed(reason: "Failed to launch gateway: \(error.localizedDescription)")
        }
    }

    private func handleTermination(exitCode: Int32) {
        process = nil
        guard !stopRequested else {
            state = .stopped
            return
        }
        restartAttempts += 1
        guard restartAttempts <= maxRestartAttempts else {
            state = .failed(reason: "Gateway exited (code \(exitCode)) and restart limit reached. See gateway.log.")
            return
        }
        let delaySeconds = Double(restartAttempts * restartAttempts)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            await self?.startOrAttach()
        }
    }

    private func isPortOpen() async -> Bool {
        // The gateway serves HTTP on the same port as the WS endpoint; any
        // response (even an error status) proves something is listening.
        var request = URLRequest(url: URL(string: "http://\(host):\(port)/")!)
        request.timeoutInterval = 1.5
        do {
            _ = try await URLSession.shared.data(for: request)
            return true
        } catch {
            return false
        }
    }
}
