import AppKit
import CoreGraphics

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

    private static let requiredFlags: CGEventFlags = [.maskControl, .maskAlternate]

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<PushToTalkMonitor>
                    .fromOpaque(userInfo).takeUnretainedValue()
                let flags = event.flags
                Task { @MainActor in
                    monitor.handleFlagsChanged(flags: flags)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        )

        guard let tap else { return }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
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

    private func handleFlagsChanged(flags: CGEventFlags) {
        let controlAndOptionHeld =
            flags.contains(.maskControl) && flags.contains(.maskAlternate)
        if controlAndOptionHeld && !isShortcutHeld {
            isShortcutHeld = true
            onPressed?()
        } else if !controlAndOptionHeld && isShortcutHeld {
            isShortcutHeld = false
            onReleased?()
        }
    }
}
