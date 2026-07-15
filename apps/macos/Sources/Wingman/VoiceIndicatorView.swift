import AppKit
import SwiftUI

/// Floating voice indicator at the bottom center of the main screen: a glassy
/// capsule with an animated waveform. Blue bars ride the live mic level while
/// listening; purple bars pulse on their own while Wingman speaks.
@MainActor
final class VoiceIndicatorController {
    private var panel: NSPanel?

    func show(speech: SpeechService, appModel: AppModel) {
        guard panel == nil, let screen = NSScreen.main else { return }

        let size = NSSize(width: 320, height: 120)
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 24
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
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
            rootView: VoiceIndicatorView()
                .environmentObject(speech)
                .environmentObject(appModel)
        )
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Which voice phase the indicator is rendering.
private enum VoicePhase: Equatable {
    case hidden
    case listening
    case thinking
    case speaking
}

struct VoiceIndicatorView: View {
    @EnvironmentObject private var speech: SpeechService
    @EnvironmentObject private var appModel: AppModel

    private var phase: VoicePhase {
        if speech.isListening { return .listening }
        if speech.isSpeaking { return .speaking }
        if appModel.voiceState == .processing { return .thinking }
        return .hidden
    }

    var body: some View {
        VStack {
            Spacer()
            if phase != .hidden {
                VoiceCapsule(phase: phase, micLevel: speech.micLevel)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.8, anchor: .bottom))
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 10)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: phase)
    }
}

private struct VoiceCapsule: View {
    let phase: VoicePhase
    let micLevel: Double

    private var tint: Color {
        switch phase {
        case .listening: Color(red: 0.11, green: 0.61, blue: 0.94)
        case .speaking: Color(red: 0.62, green: 0.40, blue: 0.96)
        case .thinking: Color(red: 0.95, green: 0.72, blue: 0.25)
        case .hidden: .clear
        }
    }

    private var label: String {
        switch phase {
        case .listening: "Listening"
        case .speaking: "Wingman"
        case .thinking: "Thinking"
        case .hidden: ""
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: phase == .listening ? "mic.fill" : "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: phase == .thinking)

            WaveformBars(phase: phase, micLevel: micLevel, tint: tint)
                .frame(width: 150, height: 34)

            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [tint.opacity(0.55), tint.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: tint.opacity(0.35), radius: 18, y: 4)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        }
    }
}

/// The vibrating bars. Driven by TimelineView so the wave flows continuously;
/// while listening, the live mic level scales the whole wave so it visibly
/// reacts to the user's voice.
private struct WaveformBars: View {
    let phase: VoicePhase
    let micLevel: Double
    let tint: Color

    private static let barCount = 22

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint, tint.opacity(0.55)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3.5)
                        .frame(height: barHeight(index: index, time: time))
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        let position = Double(index) / Double(Self.barCount - 1)
        // Center-weighted envelope: tall in the middle, short at the edges.
        let envelope = 0.35 + 0.65 * sin(position * .pi)

        // Two traveling sine waves at different speeds give an organic ripple.
        let wave1 = sin(time * 6.5 + position * 9)
        let wave2 = sin(time * 3.7 - position * 5 + 1.3)
        let ripple = (wave1 * 0.6 + wave2 * 0.4 + 1) / 2 // 0...1

        let energy: Double
        switch phase {
        case .listening:
            // Idle shimmer plus strong response to actual voice level.
            energy = 0.15 + micLevel * 0.85
        case .speaking:
            energy = 0.55 + 0.35 * sin(time * 2.1 + position * 2)
        case .thinking:
            energy = 0.22
        case .hidden:
            energy = 0
        }

        let minHeight = 4.0
        let maxHeight = 34.0
        let height = minHeight + (maxHeight - minHeight) * envelope * ripple * energy
        return CGFloat(max(height, minHeight))
    }
}
