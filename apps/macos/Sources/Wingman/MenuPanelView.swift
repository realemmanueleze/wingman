import SwiftUI

/// Menu bar dropdown: gateway status, mode picker, permissions, buddy toggle.
struct MenuPanelView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            Button {
                appModel.openChatWindow()
            } label: {
                Label("Open chat", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            modePicker
            Toggle("Show buddy cursor", isOn: $appModel.showBuddy)
                .toggleStyle(.switch)
            Divider()
            permissionsSection
            if let error = appModel.lastErrorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { appModel.permissions.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Wingman").font(.headline)
                Spacer()
                statusPill
            }
            Text("Hold ⌃⌥ anywhere and talk.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch appModel.gatewaySidecar.state {
            case .running: return ("gateway running", .green)
            case .attachedToExternal: return ("attached", .green)
            case .starting: return ("starting…", .orange)
            case .stopped: return ("stopped", .secondary)
            case .failed: return ("gateway error", .red)
            }
        }()
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode").font(.caption).foregroundStyle(.secondary)
            Picker("Mode", selection: $appModel.turnMode) {
                ForEach(TurnMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(modeCaption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var modeCaption: String {
        switch appModel.turnMode {
        case .teach: return "Explains and points. Never runs tools."
        case .askBeforeAct: return "Can use tools, but asks before anything risky."
        case .act: return "Full agent: shell, files, browser under gateway policy."
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Permissions").font(.caption).foregroundStyle(.secondary)
            permissionRow(
                name: "Screen Recording",
                granted: appModel.permissions.hasScreenRecording
            ) { appModel.permissions.requestScreenRecording() }
            permissionRow(
                name: "Microphone",
                granted: appModel.permissions.hasMicrophone
            ) { appModel.permissions.requestMicrophone() }
            permissionRow(
                name: "Accessibility (hotkey)",
                granted: appModel.permissions.hasAccessibility
            ) { appModel.permissions.requestAccessibility() }
            permissionRow(
                name: "Speech Recognition",
                granted: appModel.permissions.hasSpeechRecognition
            ) { appModel.permissions.requestSpeechRecognition() }
        }
    }

    private func permissionRow(
        name: String, granted: Bool, request: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
            Text(name).font(.caption)
            Spacer()
            if !granted {
                Button("Grant", action: request)
                    .font(.caption)
                    .buttonStyle(.link)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Setup…") {
                appModel.openOnboardingWindow()
            }
            .font(.caption)
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .font(.caption)
        }
    }
}
