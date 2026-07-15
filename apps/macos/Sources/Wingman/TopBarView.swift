import AppKit
import SwiftUI

/// The "halo" — a slim living line at the top center of the screen.
///
/// Asleep it is a quiet shimmering strand that tints with voice activity.
/// Hovering wakes it into a floating command deck with two tabs: Control
/// (status, mode, quick actions) and Sessions (AI history browser). The
/// cursor leaving the deck puts it back to sleep.
@MainActor
final class TopBarController {
    static let collapsedSize = NSSize(width: 210, height: 26)
    static let expandedSize = NSSize(width: 540, height: 430)

    private var panel: NSPanel?
    private weak var appModel: AppModel?
    private(set) var isExpanded = false

    func show(appModel: AppModel) {
        guard panel == nil, let screen = NSScreen.main else { return }
        self.appModel = appModel

        let panel = NSPanel(
            contentRect: frame(expanded: false, screen: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(
            rootView: TopBarView(controller: self)
                .environmentObject(appModel)
                .environmentObject(appModel.speech)
                .environmentObject(appModel.gatewayClient)
        )
        host.frame = NSRect(origin: .zero, size: Self.collapsedSize)
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded, let panel, let screen = NSScreen.main else { return }
        isExpanded = expanded
        panel.setFrame(frame(expanded: expanded, screen: screen), display: true, animate: false)
        panel.contentView?.frame = NSRect(
            origin: .zero,
            size: expanded ? Self.expandedSize : Self.collapsedSize
        )
    }

    /// Top-center, hugging the menu bar; the top edge stays pinned so the
    /// deck grows downward from the line.
    private func frame(expanded: Bool, screen: NSScreen) -> NSRect {
        let size = expanded ? Self.expandedSize : Self.collapsedSize
        let topY = screen.visibleFrame.maxY - 2
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: topY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - Palette

/// One accent, one solid body color. No gradients.
private enum Deck {
    static let accent = Color(red: 0.38, green: 0.62, blue: 1.0)
    static let speaking = Color(red: 0.68, green: 0.48, blue: 1.0)
    static let thinking = Color(red: 0.98, green: 0.75, blue: 0.30)
    static let body = Color(red: 0.075, green: 0.078, blue: 0.10)
    static let card = Color.white.opacity(0.055)
    static let cardHover = Color.white.opacity(0.10)
}

// MARK: - Root view

struct TopBarView: View {
    let controller: TopBarController

    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var speech: SpeechService

    @State private var expanded = false
    @State private var collapseWorkItem: DispatchWorkItem?

    var body: some View {
        ZStack(alignment: .top) {
            if expanded {
                CommandDeck()
                    .transition(
                        .scale(scale: 0.6, anchor: .top).combined(with: .opacity)
                    )
            } else {
                SleepingLine(
                    isListening: speech.isListening,
                    isSpeaking: speech.isSpeaking,
                    isThinking: appModel.voiceState == .processing,
                    micLevel: speech.micLevel
                )
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering in
            collapseWorkItem?.cancel()
            if hovering {
                setExpanded(true)
            } else {
                // Grace period so brushing the edge doesn't slam it shut.
                let work = DispatchWorkItem { setExpanded(false) }
                collapseWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: expanded)
    }

    private func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        // Grow the window first so the deck has room; shrink it after the
        // collapse animation would have finished.
        if value {
            controller.setExpanded(true)
            expanded = true
        } else {
            expanded = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !expanded { controller.setExpanded(false) }
            }
        }
    }
}

// MARK: - Sleeping line

/// The collapsed state: a thin luminous strand. It breathes gently when idle
/// and glows with the voice phase color; a soft brighter dot drifts along it
/// so it always feels alive.
private struct SleepingLine: View {
    let isListening: Bool
    let isSpeaking: Bool
    let isThinking: Bool
    let micLevel: Double

    private var tint: Color {
        if isListening { return Deck.accent }
        if isSpeaking { return Deck.speaking }
        if isThinking { return Deck.thinking }
        return Color.white
    }

    private var isActive: Bool { isListening || isSpeaking || isThinking }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let breathe = 0.5 + 0.5 * sin(time * 1.4)
            let energy = isListening ? 0.35 + micLevel * 0.65 : (isActive ? 0.7 : 0.28 + breathe * 0.18)
            let height: CGFloat = isActive ? 5.5 : 4
            let drift = (sin(time * 1.1) + 1) / 2 // 0...1 sweep position

            Capsule()
                .fill(tint.opacity(0.35 + energy * 0.35))
                .overlay {
                    // A drifting glow spot keeps the strand feeling alive
                    // without painting the whole line in gradients.
                    GeometryReader { geo in
                        Circle()
                            .fill(tint.opacity(0.9))
                            .frame(width: height * 2.4, height: height * 2.4)
                            .blur(radius: 3)
                            .position(
                                x: geo.size.width * drift,
                                y: geo.size.height / 2
                            )
                    }
                }
                .clipShape(Capsule())
                .frame(width: 150, height: height)
                .shadow(color: tint.opacity(0.35 * energy + 0.1), radius: 6, y: 1)
                .shadow(color: tint.opacity(0.2 * energy), radius: 14, y: 2)
        }
    }
}

// MARK: - Deck shape

/// The deck silhouette: a narrow neck hanging from the menu bar that flares
/// smoothly outward into a wide body with softly rounded bottom corners.
private struct DeckShape: Shape {
    var neckWidth: CGFloat = 220
    var flareHeight: CGFloat = 56
    var cornerRadius: CGFloat = 42

    func path(in rect: CGRect) -> Path {
        let neckLeft = rect.midX - neckWidth / 2
        let neckRight = rect.midX + neckWidth / 2
        var path = Path()

        path.move(to: CGPoint(x: neckLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: neckRight, y: rect.minY))
        // Right flare: an S-curve from the neck out to the full width.
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + flareHeight),
            control1: CGPoint(x: neckRight + 10, y: rect.minY + flareHeight * 0.75),
            control2: CGPoint(x: rect.maxX - 30, y: rect.minY + flareHeight * 0.25)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + flareHeight))
        // Left flare mirrors the right.
        path.addCurve(
            to: CGPoint(x: neckLeft, y: rect.minY),
            control1: CGPoint(x: rect.minX + 30, y: rect.minY + flareHeight * 0.25),
            control2: CGPoint(x: neckLeft - 10, y: rect.minY + flareHeight * 0.75)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Command deck

private enum DeckTab: String, CaseIterable {
    case control = "Control"
    case sessions = "Sessions"

    var icon: String {
        switch self {
        case .control: "circle.hexagongrid.fill"
        case .sessions: "clock.arrow.circlepath"
        }
    }
}

private struct CommandDeck: View {
    @State private var tab: DeckTab = .control

    private static let shape = DeckShape()

    var body: some View {
        VStack(spacing: 0) {
            // The neck: a small live waveform where the sleeping line was.
            DeckWaveform()
                .frame(width: 130, height: 24)
                .padding(.top, 8)

            DeckTabBar(tab: $tab)
                .padding(.top, 26)
                .padding(.horizontal, 26)

            Group {
                switch tab {
                case .control: ControlTab()
                case .sessions: SessionsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
        }
        .frame(width: 520, height: 410)
        .background {
            Self.shape
                .fill(Deck.body)
                .overlay {
                    Self.shape.stroke(.white.opacity(0.09), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        }
        .clipShape(Self.shape)
        .environment(\.colorScheme, .dark)
    }
}

private struct DeckTabBar: View {
    @Binding var tab: DeckTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DeckTab.allCases, id: \.self) { candidate in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        tab = candidate
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: candidate.icon).font(.system(size: 11, weight: .semibold))
                        Text(candidate.rawValue)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background {
                        Capsule().fill(tab == candidate ? Deck.accent : Color.white.opacity(0.06))
                    }
                    .foregroundStyle(tab == candidate ? Color.black : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            StatusPill()
        }
    }
}

private struct StatusPill: View {
    @EnvironmentObject private var gateway: GatewayClient

    private var connected: Bool {
        gateway.connectionState == .connected
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .shadow(color: (connected ? Color.green : .orange).opacity(0.8), radius: 4)
            Text(connected ? "online" : "connecting")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Deck.card))
    }
}

// MARK: - Control tab

private struct ControlTab: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var speech: SpeechService

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Live voice strip — the deck's heartbeat.
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Deck.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voiceHeadline)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("Hold ⌃⌥ anywhere and talk")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background {
                Capsule().fill(Deck.card)
            }

            // Mode selector.
            VStack(alignment: .leading, spacing: 8) {
                Text("MODE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .kerning(1.2)
                HStack(spacing: 8) {
                    ForEach(TurnMode.allCases) { mode in
                        ModeChip(mode: mode, selected: appModel.turnMode == mode) {
                            appModel.turnMode = mode
                        }
                    }
                }
            }

            Spacer()

            // Quick actions.
            HStack(spacing: 10) {
                DeckButton(icon: "bubble.left.and.text.bubble.right.fill", title: "Open chat", prominent: true) {
                    appModel.openChatWindow()
                }
                DeckButton(icon: "gearshape.fill", title: "Setup", prominent: false) {
                    appModel.openOnboardingWindow()
                }
                Spacer()
                Toggle(isOn: $appModel.showBuddy) {
                    Text("Buddy")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Deck.accent)
            }
        }
    }

    private var voiceHeadline: String {
        if speech.isListening { return "Listening…" }
        if speech.isSpeaking { return "Speaking" }
        if appModel.voiceState == .processing { return "Thinking…" }
        return "Ready"
    }
}

private struct ModeChip: View {
    let mode: TurnMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(mode.displayName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background {
                    Capsule().fill(selected ? Deck.accent : Color.white.opacity(0.06))
                }
                .foregroundStyle(selected ? Color.black : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}

private struct DeckButton: View {
    let icon: String
    let title: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 10)
            .background {
                Capsule().fill(prominent ? Deck.accent : Color.white.opacity(0.08))
            }
            .foregroundStyle(prominent ? Color.black : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Miniature always-on waveform for the deck header.
private struct DeckWaveform: View {
    @EnvironmentObject private var speech: SpeechService

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<16, id: \.self) { index in
                    let position = Double(index) / 15.0
                    let envelope = 0.4 + 0.6 * sin(position * .pi)
                    let ripple = (sin(time * 5 + position * 8) + 1) / 2
                    let energy: Double = speech.isListening
                        ? 0.2 + speech.micLevel * 0.8
                        : (speech.isSpeaking ? 0.6 : 0.18)
                    Capsule()
                        .fill(Deck.accent)
                        .frame(width: 3, height: max(3, 26 * envelope * ripple * energy + 3))
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

// MARK: - Sessions tab

private struct SessionsTab: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedSession: GatewayClient.SessionSummary?

    var body: some View {
        Group {
            if let session = selectedSession {
                SessionDetail(session: session) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selectedSession = nil
                    }
                }
            } else {
                sessionList
            }
        }
        .onAppear { appModel.refreshSessions() }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT SESSIONS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .kerning(1.2)
                Spacer()
                Button {
                    appModel.refreshSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if appModel.isLoadingSessions && appModel.sessionSummaries.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                Spacer()
            } else if appModel.sessionSummaries.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text("No sessions yet — say something!")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(appModel.sessionSummaries) { session in
                            SessionRow(session: session) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    selectedSession = session
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct SessionRow: View {
    let session: GatewayClient.SessionSummary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: session.key.contains("teach") ? "graduationcap.fill" : "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(Deck.accent)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.07)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    if let preview = session.preview, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let updatedAt = session.updatedAt {
                    Text(updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(hovering ? Deck.cardHover : Deck.card)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SessionDetail: View {
    let session: GatewayClient.SessionSummary
    let onBack: () -> Void

    @EnvironmentObject private var appModel: AppModel
    @State private var messages: [GatewayClient.HistoryMessage] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
            }

            if loading {
                Spacer()
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                Spacer()
            } else if messages.isEmpty {
                Spacer()
                Text("No messages in this session.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { message in
                                HistoryBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.never)
                    .onAppear {
                        if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
        .task(id: session.key) {
            loading = true
            messages = await appModel.loadHistory(sessionKey: session.key)
            loading = false
        }
    }
}

private struct HistoryBubble: View {
    let message: GatewayClient.HistoryMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.text)
                .font(.system(size: 12, design: .rounded))
                .textSelection(.enabled)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isUser ? Deck.accent : Color.white.opacity(0.07))
                }
                .foregroundStyle(isUser ? Color.black : Color.primary)
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
