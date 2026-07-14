import AppKit
import SwiftUI

/// First-run setup wizard: Welcome → Permissions → AI provider → Try it.
/// The whole flow a non-technical user needs — no terminal, ever.
struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var onboarding: OnboardingManager

    enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case provider
        case done
    }

    @State private var step: Step = .welcome
    @State private var selectedProvider: OnboardingManager.Provider = .anthropic
    @State private var apiKey = ""
    @State private var model = OnboardingManager.Provider.anthropic.defaultModel
    @State private var setupErrorText: String?
    @State private var providerAlreadyConfigured = OnboardingManager.isGatewayConfigured()

    init(onboarding: OnboardingManager) {
        self.onboarding = onboarding
    }

    private static let assemblBlue = Color(red: 0x1D / 255.0, green: 0x9B / 255.0, blue: 0xF0 / 255.0)

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            Divider()
            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
        }
        .frame(width: 520, height: 480)
        .onAppear { appModel.permissions.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .permissions: permissionsStep
        case .provider: providerStep
        case .done: doneStep
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "cursorarrow.rays")
                .font(.system(size: 44))
                .foregroundStyle(Self.assemblBlue)
            Text("Welcome to Wingman").font(.largeTitle.bold())
            Text("Your AI wingman lives in the menu bar. It can see your screen, talk with you, point at things, and — when you allow it — do real work on your Mac.")
                .foregroundStyle(.secondary)
            Text("This quick setup takes about two minutes.")
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let Wingman see and hear").font(.title.bold())
            Text("macOS will ask you to approve each of these. They're what make the magic work.")
                .foregroundStyle(.secondary)

            permissionCard(
                icon: "rectangle.dashed.badge.record",
                title: "Screen Recording",
                detail: "So Wingman can see what you see and point at things.",
                granted: appModel.permissions.hasScreenRecording
            ) { appModel.permissions.requestScreenRecording() }

            permissionCard(
                icon: "mic.fill",
                title: "Microphone & Speech",
                detail: "So you can hold a key and just talk.",
                granted: appModel.permissions.hasMicrophone && appModel.permissions.hasSpeechRecognition
            ) {
                appModel.permissions.requestMicrophone()
                appModel.permissions.requestSpeechRecognition()
            }

            permissionCard(
                icon: "keyboard",
                title: "Accessibility",
                detail: "So the ⌃⌥ push-to-talk shortcut works in any app.",
                granted: appModel.permissions.hasAccessibility
            ) { appModel.permissions.requestAccessibility() }

            Button("Re-check") { appModel.permissions.refresh() }
                .buttonStyle(.link)
        }
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your AI").font(.title.bold())

            if providerAlreadyConfigured {
                Label(
                    "An AI provider is already configured — you can skip this step or update the key.",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
            }

            Text("Wingman runs on your own AI account. Pick a provider and paste an API key — it stays on this Mac.")
                .foregroundStyle(.secondary)

            Picker("Provider", selection: $selectedProvider) {
                ForEach(OnboardingManager.Provider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: selectedProvider) { _, newProvider in
                model = newProvider.defaultModel
            }

            SecureField("Paste your API key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text("Model:").foregroundStyle(.secondary)
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
            }
            .font(.callout)

            Button("Where do I get a key?") {
                if let url = URL(string: selectedProvider.keyConsoleURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)

            if let setupErrorText {
                Text(setupErrorText).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("You're all set").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 8) {
                howToRow(number: "1", text: "Hold ⌃ Control + ⌥ Option anywhere")
                howToRow(number: "2", text: "Ask something — \u{201C}what am I looking at?\u{201D}")
                howToRow(number: "3", text: "Release. Wingman answers out loud and points.")
            }
            Text("Find Wingman anytime in the menu bar. Start in Teach mode; switch to Act when you want it to do things for you.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .welcome
                }
            }
            Spacer()
            ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                .frame(width: 120)
            Spacer()
            Button(primaryButtonTitle) { advance() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryButtonTitle: String {
        switch step {
        case .welcome: return "Get started"
        case .permissions: return "Continue"
        case .provider: return providerAlreadyConfigured && apiKey.isEmpty ? "Skip" : "Save & continue"
        case .done: return "Start using Wingman"
        }
    }

    private func advance() {
        setupErrorText = nil
        switch step {
        case .welcome:
            step = .permissions
        case .permissions:
            appModel.permissions.refresh()
            step = .provider
        case .provider:
            if providerAlreadyConfigured && apiKey.isEmpty {
                step = .done
                return
            }
            do {
                try OnboardingManager.writeProviderConfig(
                    provider: selectedProvider, apiKey: apiKey, model: model
                )
                providerAlreadyConfigured = true
                appModel.restartGateway()
                step = .done
            } catch {
                setupErrorText = error.localizedDescription
            }
        case .done:
            OnboardingManager.hasCompletedOnboarding = true
            appModel.finishOnboarding()
        }
    }

    private func permissionCard(
        icon: String, title: String, detail: String, granted: Bool, request: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(Self.assemblBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Button("Allow", action: request)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func howToRow(number: String, text: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Self.assemblBlue, in: Circle())
                .foregroundStyle(.white)
            Text(text)
        }
    }
}
