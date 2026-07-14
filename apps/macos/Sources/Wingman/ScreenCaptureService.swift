import AppKit
import ScreenCaptureKit

/// One captured display, labeled for the vision model. Coordinates in
/// `displayFrame` are AppKit global points (bottom-left origin) so downstream
/// pointing math shares one coordinate system with NSEvent.mouseLocation.
struct ScreenCapture {
    let jpegData: Data
    let label: String
    let isCursorScreen: Bool
    let displayFrame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Multi-display snapshot capture via ScreenCaptureKit, following Clicky's
/// CompanionScreenCaptureUtility: cursor screen sorted first, own windows
/// excluded so the model never sees Wingman's overlay, output downscaled to
/// keep vision payloads small.
@MainActor
enum ScreenCaptureService {
    static let maxDimension = 1280

    static func captureAllDisplays() async throws -> [ScreenCapture] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard !content.displays.isEmpty else {
            throw NSError(
                domain: "Wingman.ScreenCapture", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No display available for capture"]
            )
        }

        let mouseLocation = NSEvent.mouseLocation
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let ownWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == ownBundleIdentifier
        }

        // SCDisplay.frame uses CG coordinates (top-left origin); NSScreen and
        // mouseLocation use AppKit coordinates (bottom-left). Build a lookup so
        // cursor-containment checks and displayFrame stay in AppKit space.
        var screenByDisplayID: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            if let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID {
                screenByDisplayID[displayID] = screen
            }
        }

        func appKitFrame(for display: SCDisplay) -> CGRect {
            screenByDisplayID[display.displayID]?.frame
                ?? CGRect(
                    x: display.frame.origin.x, y: display.frame.origin.y,
                    width: CGFloat(display.width), height: CGFloat(display.height)
                )
        }

        let sortedDisplays = content.displays.sorted { a, b in
            let aHasCursor = appKitFrame(for: a).contains(mouseLocation)
            let bHasCursor = appKitFrame(for: b).contains(mouseLocation)
            if aHasCursor != bHasCursor { return aHasCursor }
            return false
        }

        var captures: [ScreenCapture] = []
        for (index, display) in sortedDisplays.enumerated() {
            let displayFrame = appKitFrame(for: display)
            let isCursorScreen = displayFrame.contains(mouseLocation)

            let filter = SCContentFilter(
                display: display, excludingWindows: ownWindows
            )
            let configuration = SCStreamConfiguration()
            let scale = min(
                1.0,
                CGFloat(maxDimension) / max(CGFloat(display.width), CGFloat(display.height))
            )
            configuration.width = Int(CGFloat(display.width) * scale)
            configuration.height = Int(CGFloat(display.height) * scale)
            configuration.showsCursor = true

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            )

            guard let jpegData = encodeJPEG(image: image, quality: 0.8) else { continue }

            let cursorSuffix = isCursorScreen
                ? " — cursor is on this screen (primary focus)" : ""
            let label = "screen \(index + 1) of \(sortedDisplays.count)\(cursorSuffix)"
                + " (image dimensions: \(image.width)x\(image.height) pixels)"

            captures.append(
                ScreenCapture(
                    jpegData: jpegData,
                    label: label,
                    isCursorScreen: isCursorScreen,
                    displayFrame: displayFrame,
                    pixelWidth: image.width,
                    pixelHeight: image.height
                )
            )
        }

        guard !captures.isEmpty else {
            throw NSError(
                domain: "Wingman.ScreenCapture", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Capture produced no images"]
            )
        }
        return captures
    }

    private static func encodeJPEG(image: CGImage, quality: Double) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        )
    }
}
