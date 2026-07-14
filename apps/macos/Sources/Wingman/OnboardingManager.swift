import Foundation

/// Replaces `openclaw onboard` for the happy path so non-technical users never
/// touch a terminal: the wizard collects a provider + API key and this writes
/// the documented OpenClaw config shape to `~/.openclaw/openclaw.json`:
///
///   { "env": { "ANTHROPIC_API_KEY": "..." },
///     "agents": { "defaults": { "model": { "primary": "anthropic/..." } } } }
///
/// Existing config is merged, never clobbered — power users who already ran
/// `openclaw onboard` keep everything they have.
@MainActor
final class OnboardingManager: ObservableObject {
    enum Provider: String, CaseIterable, Identifiable {
        case anthropic
        case openai

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .anthropic: return "Anthropic (Claude)"
            case .openai: return "OpenAI (GPT)"
            }
        }

        var envKey: String {
            switch self {
            case .anthropic: return "ANTHROPIC_API_KEY"
            case .openai: return "OPENAI_API_KEY"
            }
        }

        var defaultModel: String {
            switch self {
            case .anthropic: return "anthropic/claude-sonnet-4-6"
            case .openai: return "openai/gpt-5.6"
            }
        }

        var keyConsoleURL: String {
            switch self {
            case .anthropic: return "https://console.anthropic.com/settings/keys"
            case .openai: return "https://platform.openai.com/api-keys"
            }
        }
    }

    static let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".openclaw", isDirectory: true)
    static let configFile = configDirectory.appendingPathComponent("openclaw.json")

    private static let onboardingCompletedKey = "wingman.onboardingCompleted"

    /// True when a usable model provider is already configured — either by our
    /// wizard or by a prior `openclaw onboard` run.
    static func isGatewayConfigured() -> Bool {
        guard let data = try? Data(contentsOf: configFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if let env = json["env"] as? [String: Any],
           env.keys.contains(where: { $0.hasSuffix("_API_KEY") }) {
            return true
        }
        // OAuth/subscription setups keep auth profiles instead of env keys.
        let authProfiles = configDirectory
            .appendingPathComponent("agents/main/agent/auth-profiles.json")
        return FileManager.default.fileExists(atPath: authProfiles.path)
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingCompletedKey) }
    }

    struct SetupError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Merges the provider key + default model into openclaw.json.
    static func writeProviderConfig(provider: Provider, apiKey: String, model: String) throws {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw SetupError(message: "Paste your API key first.")
        }

        var config: [String: Any] = [:]
        if let data = try? Data(contentsOf: configFile),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }

        var env = config["env"] as? [String: Any] ?? [:]
        env[provider.envKey] = trimmedKey
        config["env"] = env

        var agents = config["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        var modelConfig = defaults["model"] as? [String: Any] ?? [:]
        modelConfig["primary"] = model.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults["model"] = modelConfig
        agents["defaults"] = defaults
        config["agents"] = agents

        // Canonical local-gateway marker so future boots don't rely on
        // --allow-unconfigured.
        var gateway = config["gateway"] as? [String: Any] ?? [:]
        if gateway["mode"] == nil { gateway["mode"] = "local" }
        config["gateway"] = gateway

        try FileManager.default.createDirectory(
            at: configDirectory, withIntermediateDirectories: true
        )
        let output = try JSONSerialization.data(
            withJSONObject: config, options: [.prettyPrinted, .sortedKeys]
        )
        try output.write(to: configFile, options: .atomic)
        // The config embeds a secret; keep it owner-only like OpenClaw does.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: configFile.path
        )
    }
}
