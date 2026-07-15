import AppKit
import CoreGraphics
import IOKit.hid

/// System-wide push-to-talk: hold ctrl+option anywhere to talk to Wingman.
///
/// Uses a listen-only CGEvent tap (Clicky's approach) because modifier-only
/// shortcuts are detected far more reliably through an event tap than an
/// AppKit global monitor while the app is in the background. Requires the
/// Accessibility permission.
@MainActor
final class PushToTalkMonitor {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isShortcutHeld = false
    private var retryTimer: Timer?

    private static let requiredFlags: CGEventFlags = [.maskControl, .maskAlternate]

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        // An active tap (not .listenOnly) that passes events through: active
        // taps are authorized by Accessibility, while listen-only keyboard
        // taps require the separate Input Monitoring permission, which is
        // denied by default and silently starves the tap of events.
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PushToTalkMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                // macOS disables slow listen-only taps; re-enable or the
                // hotkey silently dies for the rest of the session.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    Task { @MainActor in monitor.reenableTap() }
                    return Unmanaged.passUnretained(event)
                }
                let flags = event.flags
                Task { @MainActor in
                    monitor.handleFlagsChanged(flags: flags)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        )

        guard let tap else {
            // Tap creation fails until Accessibility is granted. Keep
            // retrying so a grant made while the app runs takes effect
            // without a relaunch.
            DebugLog.write("PushToTalk: tap creation FAILED (AXIsProcessTrusted: \(AXIsProcessTrusted())) — retrying in 3s")
            scheduleRetry()
            return
        }
        retryTimer?.invalidate()
        retryTimer = nil
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        // Tap creation can succeed while event delivery is silently blocked;
        // record both trust states so a dead hotkey is diagnosable.
        let axTrusted = AXIsProcessTrusted()
        let inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        DebugLog.write(
            "PushToTalk: event tap active (axTrusted=\(axTrusted) inputMonitoring=\(inputMonitoring.rawValue) 0=granted/1=denied/2=unknown)"
        )
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isShortcutHeld = false
    }

    private func scheduleRetry() {
        guard retryTimer == nil else { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
                self.start()
            }
        }
    }

    private func reenableTap() {
        if let tap = eventTap {
            DebugLog.write("PushToTalk: tap was disabled by system, re-enabling")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func handleFlagsChanged(flags: CGEventFlags) {
        let controlAndOptionHeld =
            flags.contains(.maskControl) && flags.contains(.maskAlternate)
        DebugLog.write(
            "PushToTalk: flagsChanged ctrl=\(flags.contains(.maskControl)) opt=\(flags.contains(.maskAlternate))"
        )
        if controlAndOptionHeld && !isShortcutHeld {
            isShortcutHeld = true
            DebugLog.write("PushToTalk: shortcut pressed")
            onPressed?()
        } else if !controlAndOptionHeld && isShortcutHeld {
            isShortcutHeld = false
            DebugLog.write("PushToTalk: shortcut released")
            onReleased?()
        }
    }
}
