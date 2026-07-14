import AppKit
import Foundation
import SwiftUI

/// Central orchestrator — Wingman's equivalent of Clicky's CompanionManager,
/// with the brain swapped for the OpenClaw Gateway.
///
/// Turn pipeline:
///   hotkey down → listen (Apple Speech) → hotkey up → capture screens →
///   gateway agent run (transcript + images + mode policy) → parse [POINT] →
///   speak response + fly buddy to target.
@MainActor
final class AppModel: ObservableObject {
    enum VoiceState: Equatable {
        case idle
        case listening
        case processing
        case responding
    }

    @Published private(set) var voiceState: VoiceState = .idle
    @Published var turnMode: TurnMode = .teach
    @Published var showBuddy = true {
        didSet { showBuddy ? overlayController.show() : overlayController.hide() }
    }
    @Published private(set) var lastResponseText = ""
    @Published private(set) var lastErrorText: String?

    // Chat window state — the typed counterpart to push-to-talk, sharing the
    // same gateway sessions, memory, and mode policy.
    @Published private(set) var chatMessages: [ChatMessage] = []
    @Published private(set) var isChatTurnRunning = false
    @Published var attachScreenToNextChatTurn = false

    let gatewaySidecar = GatewaySidecar()
    let gatewayClient = GatewayClient()
    let permissions = PermissionsManager()
    let speech = SpeechService()
    let onboarding = OnboardingManager()

    private let overlayController = OverlayWindowController()
    private let pushToTalk = PushToTalkMonitor()
    private var currentTurnTask: Task<Void, Never>?
    private var chatWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private var overlayModel: OverlayModel { overlayController.overlayModel }

    // MARK: - Lifecycle

    func start() {
        permissions.refresh()
        gatewaySidecar.start()

        pushToTalk.onPressed = { [weak self] in self?.beginListening() }
        pushToTalk.onReleased = { [weak self] in self?.finishListeningAndRespond() }
        pushToTalk.start()

        if showBuddy {
            overlayController.show()
        }

        Task { await connectToGatewayWhenReady() }

        // First run (or missing provider config): open the setup wizard so
        // non-technical users never need a terminal.
        if !OnboardingManager.hasCompletedOnboarding || !OnboardingManager.isGatewayConfigured() {
            openOnboardingWindow()
        }
    }

    func shutdown() {
        pushToTalk.stop()
        speech.stopSpeaking()
        gatewayClient.disconnect()
        gatewaySidecar.stop()
        overlayController.hide()
    }

    private func connectToGatewayWhenReady() async {
        // The sidecar needs a moment to boot; retry with backoff.
        for attempt in 1...10 {
            if case .failed = gatewaySidecar.state { return }
            do {
                try await gatewayClient.connect(
                    url: gatewaySidecar.webSocketURL,
                    token: gatewaySidecar.authToken
                )
                return
            } catch {
                let delay = min(Double(attempt) * 1.5, 8.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    // MARK: - Turn pipeline

    private func beginListening() {
        guard voiceState == .idle else { return }
        guard permissions.hasMicrophone else {
            permissions.requestMicrophone()
            return
        }
        speech.stopSpeaking()
        do {
            try speech.startListening()
            voiceState = .listening
            overlayModel.activity = .listening
        } catch {
            lastErrorText = "Could not start microphone: \(error.localizedDescription)"
        }
    }

    private func finishListeningAndRespond() {
        guard voiceState == .listening else { return }
        voiceState = .processing
        overlayModel.activity = .processing

        currentTurnTask?.cancel()
        currentTurnTask = Task { [weak self] in
            guard let self else { return }
            let transcript = await self.speech.stopListening()
            guard !transcript.isEmpty else {
                self.resetToIdle()
                return
            }
            await self.runTurn(transcript: transcript)
        }
    }

    private func runTurn(transcript: String) async {
        let policy = TurnPolicy.resolve(mode: turnMode)
        lastErrorText = nil

        do {
            var captures: [ScreenCapture] = []
            if policy.attachScreenCaptures, permissions.hasScreenRecording {
                captures = try await ScreenCaptureService.captureAllDisplays()
            }
            guard !Task.isCancelled else { return }

            // Screen labels ride in the message so the model knows the
            // coordinate space of each attached image.
            var message = transcript
            if !captures.isEmpty {
                let labels = captures.map { "- \($0.label)" }.joined(separator: "\n")
                message += "\n\n[attached screenshots]\n\(labels)"
            }

            let responseText = try await gatewayClient.runAgentTurn(
                message: message,
                sessionKey: policy.sessionKey,
                extraSystemPrompt: policy.systemPromptFragments.joined(separator: "\n\n"),
                imageAttachments: captures.map { (data: $0.jpegData, mimeType: "image/jpeg") }
            )
            guard !Task.isCancelled else { return }

            let parsed = PointTag.parse(responseText)
            lastResponseText = parsed.spokenText

            if let target = parsed.target,
               let globalPoint = PointTag.mapToGlobalPoint(target: target, captures: captures) {
                overlayModel.activity = .pointing(label: target.label)
                overlayModel.pointTarget = globalPoint
            } else {
                overlayModel.activity = .idle
                overlayModel.pointTarget = nil
            }

            voiceState = .responding
            speech.speak(parsed.spokenText)

            // Return the buddy to the mouse after the pointing moment passes.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.overlayModel.pointTarget = nil
                    if case .pointing = self.overlayModel.activity {
                        self.overlayModel.activity = .idle
                    }
                    if self.voiceState == .responding {
                        self.voiceState = .idle
                    }
                }
            }
        } catch {
            lastErrorText = error.localizedDescription
            resetToIdle()
        }
    }

    private func resetToIdle() {
        voiceState = .idle
        overlayModel.activity = .idle
        overlayModel.pointTarget = nil
    }

    // MARK: - Chat turns (typed)

    func sendChatMessage(_ text: String) {
        guard !isChatTurnRunning else { return }
        let wantsScreen = attachScreenToNextChatTurn
        attachScreenToNextChatTurn = false
        chatMessages.append(
            ChatMessage(role: .user, text: text, includedScreenCapture: wantsScreen)
        )
        isChatTurnRunning = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isChatTurnRunning = false }
            let policy = TurnPolicy.resolve(mode: self.turnMode)
            do {
                var captures: [ScreenCapture] = []
                if wantsScreen, self.permissions.hasScreenRecording {
                    captures = try await ScreenCaptureService.captureAllDisplays()
                }
                var message = text
                if !captures.isEmpty {
                    let labels = captures.map { "- \($0.label)" }.joined(separator: "\n")
                    message += "\n\n[attached screenshots]\n\(labels)"
                }
                // Typed turns read on screen, so skip the voice-style prompt
                // but keep mode + pointing contracts.
                let promptFragments = policy.systemPromptFragments.filter {
                    $0 != TurnPolicy.voiceStylePrompt
                }
                let responseText = try await self.gatewayClient.runAgentTurn(
                    message: message,
                    sessionKey: policy.sessionKey,
                    extraSystemPrompt: promptFragments.joined(separator: "\n\n"),
                    imageAttachments: captures.map { (data: $0.jpegData, mimeType: "image/jpeg") }
                )
                let parsed = PointTag.parse(responseText)
                self.chatMessages.append(
                    ChatMessage(role: .assistant, text: parsed.spokenText, includedScreenCapture: false)
                )
                if let target = parsed.target,
                   let globalPoint = PointTag.mapToGlobalPoint(target: target, captures: captures) {
                    self.overlayModel.activity = .pointing(label: target.label)
                    self.overlayModel.pointTarget = globalPoint
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 6_000_000_000)
                        await MainActor.run {
                            self?.overlayModel.pointTarget = nil
                            if case .pointing = self?.overlayModel.activity {
                                self?.overlayModel.activity = .idle
                            }
                        }
                    }
                }
            } catch {
                self.chatMessages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "Something went wrong: \(error.localizedDescription)",
                        includedScreenCapture: false
                    )
                )
            }
        }
    }

    // MARK: - Windows

    func openChatWindow() {
        if let chatWindow {
            chatWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: ChatView().environmentObject(self))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Wingman"
        window.setContentSize(NSSize(width: 520, height: 620))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        chatWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOnboardingWindow() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(
            rootView: OnboardingView(onboarding: onboarding).environmentObject(self)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Set up Wingman"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finishOnboarding() {
        onboardingWindow?.close()
        onboardingWindow = nil
        openChatWindow()
    }

    /// Restarts the gateway sidecar so freshly written provider config takes
    /// effect, then reconnects the client.
    func restartGateway() {
        gatewayClient.disconnect()
        gatewaySidecar.stop()
        gatewaySidecar.start()
        Task { await connectToGatewayWhenReady() }
    }
}

// MARK: - Chat message model

struct ChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let includedScreenCapture: Bool
}
