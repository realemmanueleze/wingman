import AppKit
import SwiftUI

/// Wingman: one desktop product combining an OpenClaw Gateway (the brain)
/// with a Clicky-style screen companion (the face).
///
/// Menu-bar-only app: no dock icon, no main window. The gateway runs as a
/// supervised sidecar process; the overlay hosts the buddy cursor.
@main
struct WingmanApp: App {
    @NSApplicationDelegateAdaptor(WingmanAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Wingman", systemImage: "cursorarrow.rays") {
            MenuPanelView()
                .environmentObject(appDelegate.appModel)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class WingmanAppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: hide from the dock and the Cmd+Tab switcher.
        NSApp.setActivationPolicy(.accessory)
        appModel.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appModel.shutdown()
    }
}
