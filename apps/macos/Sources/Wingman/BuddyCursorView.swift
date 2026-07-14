import AppKit
import SwiftUI

/// The buddy: a small triangle that trails the mouse and flies to pointing
/// targets. Assembl Blue (#1d9bf0). Rendering is local to each screen's
/// overlay panel; global AppKit coordinates convert to local view space here.
struct BuddyCursorView: View {
    @ObservedObject var overlayModel: OverlayModel
    let screenFrame: CGRect

    @State private var buddyPosition = CGPoint(x: 200, y: 200)
    @State private var isVisibleOnThisScreen = false

    private static let assemblBlue = Color(red: 0x1D / 255.0, green: 0x9B / 255.0, blue: 0xF0 / 255.0)
    private let mouseTimer = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            if isVisibleOnThisScreen {
                buddyBody
                    .position(buddyPosition)
                    .animation(.spring(response: 0.55, dampingFraction: 0.75), value: buddyPosition)
                if case .pointing(let label) = overlayModel.activity, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Self.assemblBlue, in: Capsule())
                        .position(x: buddyPosition.x, y: buddyPosition.y - 30)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(mouseTimer) { _ in
            updatePosition()
        }
    }

    private var buddyBody: some View {
        Triangle()
            .fill(Self.assemblBlue)
            .frame(width: 18, height: 18)
            .shadow(color: Self.assemblBlue.opacity(0.5), radius: pulseRadius)
    }

    private var pulseRadius: CGFloat {
        switch overlayModel.activity {
        case .listening: return 10
        case .processing: return 6
        default: return 3
        }
    }

    private func updatePosition() {
        // Pointing target wins; otherwise trail the mouse with a small offset.
        let globalTarget: CGPoint
        if let target = overlayModel.pointTarget {
            globalTarget = target
        } else {
            let mouse = NSEvent.mouseLocation
            globalTarget = CGPoint(x: mouse.x + 24, y: mouse.y - 8)
        }

        let onThisScreen = screenFrame.contains(globalTarget)
        isVisibleOnThisScreen = onThisScreen
        guard onThisScreen else { return }

        // Global AppKit (bottom-left origin) → local SwiftUI (top-left origin).
        let localX = globalTarget.x - screenFrame.origin.x
        let localY = screenFrame.height - (globalTarget.y - screenFrame.origin.y)
        buddyPosition = CGPoint(x: localX, y: localY)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
