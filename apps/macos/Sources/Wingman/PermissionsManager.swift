import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

/// macOS TCC permission flow, adapted from Clicky's WindowPositionManager.
///
/// Strategy per permission: preflight → system prompt once → deep-link to the
/// System Settings pane on later attempts (never both at once). A UserDefaults
/// flag works around the known CGPreflightScreenCaptureAccess false-negative
/// flicker after a prior grant.
@MainActor
final class PermissionsManager: ObservableObject {
    @Published private(set) var hasScreenRecording = false
    @Published private(set) var hasMicrophone = false
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasSpeechRecognition = false

    private var hasAttemptedScreenRecordingPromptThisLaunch = false
    private static let confirmedScreenRecordingKey = "wingman.hasPreviouslyConfirmedScreenRecording"

    var allGranted: Bool {
        hasScreenRecording && hasMicrophone && hasAccessibility
    }

    func refresh() {
        let preflight = CGPreflightScreenCaptureAccess()
        if preflight {
            UserDefaults.standard.set(true, forKey: Self.confirmedScreenRecordingKey)
        }
        // Treat a previously confirmed grant as granted even if preflight
        // flickers false — re-prompting a user who already granted is worse.
        hasScreenRecording = preflight
            || UserDefaults.standard.bool(forKey: Self.confirmedScreenRecordingKey)

        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibility = AXIsProcessTrusted()
        hasSpeechRecognition = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    func requestScreenRecording() {
        if CGPreflightScreenCaptureAccess() {
            refresh()
            return
        }
        if hasAttemptedScreenRecordingPromptThisLaunch {
            openSettingsPane("Privacy_ScreenCapture")
        } else {
            hasAttemptedScreenRecordingPromptThisLaunch = true
            _ = CGRequestScreenCaptureAccess()
        }
        refresh()
    }

    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        case .denied, .restricted:
            openSettingsPane("Privacy_Microphone")
        default:
            break
        }
        refresh()
    }

    func requestAccessibility() {
        if !AXIsProcessTrusted() {
            let promptKey = "AXTrustedCheckOptionPrompt" as CFString
            let options = [promptKey: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        refresh()
    }

    func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func openSettingsPane(_ pane: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
