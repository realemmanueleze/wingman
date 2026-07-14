import AppKit
import SwiftUI

/// Full-screen transparent, click-through overlay hosting the buddy cursor —
/// Clicky's OverlayWindow pattern. Non-activating, joins all Spaces, floats
/// at screen-saver level, never steals focus.
@MainActor
final class OverlayWindowController {
    private var panels: [NSPanel] = []
    let overlayModel = OverlayModel()

    func show() {
        guard panels.isEmpty else { return }
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false

            let host = NSHostingView(
                rootView: BuddyCursorView(
                    overlayModel: overlayModel,
                    screenFrame: screen.frame
                )
            )
            host.frame = NSRect(origin: .zero, size: screen.frame.size)
            panel.contentView = host
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

/// Shared overlay state: buddy activity + pointing target in global AppKit coords.
@MainActor
final class OverlayModel: ObservableObject {
    enum Activity: Equatable {
        case idle
        case listening
        case processing
        case pointing(label: String)
    }

    @Published var activity: Activity = .idle
    /// Global AppKit point the buddy should fly to; nil returns it to the mouse.
    @Published var pointTarget: CGPoint?
}
