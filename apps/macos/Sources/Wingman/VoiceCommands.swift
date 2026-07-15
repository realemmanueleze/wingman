import Foundation

/// Local voice-command routing: app-control phrases ("act mode", "open chat",
/// "stop talking") are handled instantly on-device instead of taking a full
/// gateway round-trip. Anything unrecognized falls through to the agent.
enum VoiceCommand: Equatable {
    case switchMode(TurnMode)
    case openChat
    case closeChat
    case showBuddy(Bool)
    case stopTalking

    /// Spoken confirmation, kept to a couple of words.
    var confirmation: String {
        switch self {
        case .switchMode(let mode):
            switch mode {
            case .teach: return "Teach mode."
            case .askBeforeAct: return "Ask-before-act mode."
            case .act: return "Act mode."
            }
        case .openChat: return "Opening chat."
        case .closeChat: return "Closing chat."
        case .showBuddy(let visible): return visible ? "Buddy on." : "Buddy off."
        case .stopTalking: return ""
        }
    }

    /// Matches a transcript against the command set. Only short utterances
    /// are considered commands: a mode name buried in a long sentence is
    /// almost certainly content for the agent, not a command.
    static func parse(_ transcript: String) -> VoiceCommand? {
        let normalized = transcript.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        let wordCount = normalized.split(separator: " ").count
        guard wordCount <= 8 else { return nil }

        func has(_ phrases: String...) -> Bool {
            phrases.contains { normalized.contains($0) }
        }

        if has("stop talking", "be quiet", "shut up", "silence") {
            return .stopTalking
        }
        if has("teach mode", "switch to teach", "point only mode") {
            return .switchMode(.teach)
        }
        if has("ask before act", "ask before acting", "ask first mode", "careful mode") {
            return .switchMode(.askBeforeAct)
        }
        if has("act mode", "action mode", "switch to act", "full mode", "do mode") {
            return .switchMode(.act)
        }
        if has("open chat", "open the chat", "show chat", "show the chat") {
            return .openChat
        }
        if has("close chat", "close the chat", "hide chat", "hide the chat") {
            return .closeChat
        }
        if has("show buddy", "show the buddy", "buddy on", "show cursor buddy") {
            return .showBuddy(true)
        }
        if has("hide buddy", "hide the buddy", "buddy off", "hide cursor buddy") {
            return .showBuddy(false)
        }
        return nil
    }
}

/// Per-turn reasoning-effort routing: short conversational asks skip the
/// model's thinking phase entirely, cutting seconds off easy turns. Anything
/// that smells like real work keeps the gateway's default effort.
enum TurnEffort {
    private static let heavyMarkers = [
        "code", "write", "fix", "build", "create", "debug", "install",
        "refactor", "script", "implement", "analyze", "analyse", "plan",
        "research", "compare", "calculate", "search", "look up",
        "step by step", "explain why", "email", "message", "run",
        "terminal", "command", "file", "folder",
    ]

    /// Returns a `thinking` override for the agent request, or nil to use
    /// the gateway default.
    static func thinkingLevel(for transcript: String) -> String? {
        let lower = transcript.lowercased()
        let wordCount = lower.split(separator: " ").count
        if wordCount <= 18, !heavyMarkers.contains(where: lower.contains) {
            return "off"
        }
        return nil
    }
}
