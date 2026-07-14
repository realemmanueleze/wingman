import SwiftUI

/// The unified work surface — a Claude-style chat window on the same gateway
/// brain as the voice buddy. Typed turns share sessions, memory, and mode
/// policy with push-to-talk turns.
struct ChatView: View {
    @EnvironmentObject private var appModel: AppModel

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private static let assemblBlue = Color(red: 0x1D / 255.0, green: 0x9B / 255.0, blue: 0xF0 / 255.0)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            composer
        }
        .frame(minWidth: 460, minHeight: 520)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack {
            Image(systemName: "cursorarrow.rays").foregroundStyle(Self.assemblBlue)
            Text("Wingman").font(.headline)
            Spacer()
            Picker("Mode", selection: $appModel.turnMode) {
                ForEach(TurnMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .frame(width: 190)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if appModel.chatMessages.isEmpty {
                        emptyState
                    }
                    ForEach(appModel.chatMessages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                    if appModel.isChatTurnRunning {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…").font(.caption).foregroundStyle(.secondary)
                        }
                        .id("thinking")
                    }
                }
                .padding(14)
            }
            .onChange(of: appModel.chatMessages.count) { _, _ in
                if let last = appModel.chatMessages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask anything — or hold ⌃⌥ and just talk.")
                .foregroundStyle(.secondary)
            Text("Attach your screen with the camera button to ask about what you're looking at.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 30)
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .textSelection(.enabled)
                if message.includedScreenCapture {
                    Label("screen attached", systemImage: "rectangle.dashed.badge.record")
                        .font(.caption2)
                        .foregroundStyle(message.role == .user ? .white.opacity(0.75) : .secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                message.role == .user ? Self.assemblBlue : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Button {
                appModel.attachScreenToNextChatTurn.toggle()
            } label: {
                Image(systemName: appModel.attachScreenToNextChatTurn
                    ? "rectangle.dashed.badge.record" : "camera")
                    .foregroundStyle(appModel.attachScreenToNextChatTurn ? Self.assemblBlue : .secondary)
            }
            .buttonStyle(.plain)
            .help("Attach a screenshot of your displays to this message")

            TextField("Message Wingman…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(draft.isEmpty ? .secondary : Self.assemblBlue)
            }
            .buttonStyle(.plain)
            .disabled(draft.isEmpty || appModel.isChatTurnRunning)
        }
        .padding(12)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !appModel.isChatTurnRunning else { return }
        draft = ""
        appModel.sendChatMessage(text)
    }
}
