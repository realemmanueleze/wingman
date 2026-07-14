import CoreGraphics
import Foundation

/// Parsing and coordinate mapping for the `[POINT:x,y:label:screenN]` contract.
/// Swift mirror of `@wingman/core` point-contract.ts.
enum PointTag {
    struct Target {
        let x: Int
        let y: Int
        let label: String
        let screenNumber: Int?
    }

    struct ParseResult {
        /// Response text with the tag removed — this is what gets spoken.
        let spokenText: String
        let target: Target?
    }

    private static let pattern =
        #"\[POINT:(?:none|(\d+)\s*,\s*(\d+)(?::([^\]:\s][^\]:]*?))?(?::screen(\d+))?)\]\s*$"#

    static func parse(_ responseText: String) -> ParseResult {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: responseText,
                range: NSRange(responseText.startIndex..., in: responseText)
              )
        else {
            return ParseResult(
                spokenText: responseText.trimmingCharacters(in: .whitespacesAndNewlines),
                target: nil
            )
        }

        let fullRange = Range(match.range, in: responseText)!
        let spokenText = String(responseText[..<fullRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        func group(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: responseText)
            else { return nil }
            return String(responseText[range])
        }

        guard let xText = group(1), let yText = group(2),
              let x = Int(xText), let y = Int(yText)
        else {
            // [POINT:none]
            return ParseResult(spokenText: spokenText, target: nil)
        }

        return ParseResult(
            spokenText: spokenText,
            target: Target(
                x: x,
                y: y,
                label: group(3)?.trimmingCharacters(in: .whitespaces) ?? "",
                screenNumber: group(4).flatMap(Int.init)
            )
        )
    }

    /// Maps a target from screenshot pixel space (top-left origin) to a global
    /// AppKit point (bottom-left origin): scale to display points, flip Y, and
    /// offset by the display's global frame origin.
    static func mapToGlobalPoint(target: Target, captures: [ScreenCapture]) -> CGPoint? {
        let capture: ScreenCapture? = {
            if let screenNumber = target.screenNumber,
               screenNumber >= 1, screenNumber <= captures.count {
                return captures[screenNumber - 1]
            }
            return captures.first(where: { $0.isCursorScreen }) ?? captures.first
        }()
        guard let capture, capture.pixelWidth > 0, capture.pixelHeight > 0 else { return nil }

        let scaleX = capture.displayFrame.width / CGFloat(capture.pixelWidth)
        let scaleY = capture.displayFrame.height / CGFloat(capture.pixelHeight)
        let pointX = capture.displayFrame.origin.x + CGFloat(target.x) * scaleX
        let pointYTopLeft = CGFloat(target.y) * scaleY
        let pointY = capture.displayFrame.origin.y + (capture.displayFrame.height - pointYTopLeft)
        return CGPoint(x: pointX, y: pointY)
    }
}
