import Foundation

/// Teach-vs-act safety policy. Swift mirror of `@wingman/core` turn-policy.ts —
/// keep the two in sync (the TS file is the canonical reference).
///
/// The client only *selects* a pre-configured gateway session per mode; tool
/// policy is enforced server-side by the gateway, which stays the source of
/// truth. Teach mode can never run tools even if a client is buggy or hostile.
enum TurnMode: String, CaseIterable, Identifiable {
    case teach
    case askBeforeAct = "ask-before-act"
    case act

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .teach: return "Teach (point only)"
        case .askBeforeAct: return "Ask before acting"
        case .act: return "Act"
        }
    }
}

struct TurnPolicy {
    let mode: TurnMode
    /// Gateway session key. Tool policy is bound to the session server-side:
    /// `wingman-teach` denies all tools; `wingman-main` is the operator session.
    let sessionKey: String
    let attachScreenCaptures: Bool
    let systemPromptFragments: [String]

    static let teachPrompt = """
    you are in TEACH mode. you can see the user's screen and explain and point, but you cannot run tools, execute commands, or modify anything. if the user asks you to perform an action, tell them to say "do it" (or switch to act mode) and describe exactly what you would do.
    """

    static let askBeforeActPrompt = """
    you are in ASK-BEFORE-ACT mode. you may use tools, but before any action that writes, deletes, sends, installs, or spends, state the exact action in one sentence and wait for approval through the exec approval flow.
    """

    static let pointingPrompt = """
    element pointing:
    you have a small cursor that can fly to and point at things on screen. when pointing at a specific UI element would genuinely help the user, append a coordinate tag at the very end of your response, AFTER your spoken text. the screenshot images are labeled with their pixel dimensions; use those dimensions as the coordinate space, origin (0,0) top-left, x rightward, y downward.

    format: [POINT:x,y:label] with integer pixel coordinates and a short 1-3 word label. if the element is on a different screen than the cursor, append :screenN using the screen number from the image label. if pointing would not help, append [POINT:none].
    """

    static let actPrompt = """
    you are in ACT mode with the full openclaw capability set available on this gateway: shell commands, file reads and writes, browsing, messaging, memory, and any other configured tools. when the user asks for an action, perform it now rather than describing what you would do, then confirm the outcome in one short spoken sentence.
    """

    static let voiceStylePrompt = """
    your reply will be spoken aloud via text-to-speech. write the way you'd actually talk: one or two direct sentences by default, all natural speech, no lists, no markdown, no symbols that sound weird read aloud. if the user's question relates to what's on their screen, reference specific things you see.
    """

    static func resolve(mode: TurnMode) -> TurnPolicy {
        switch mode {
        case .teach:
            return TurnPolicy(
                mode: mode,
                sessionKey: "wingman-teach",
                attachScreenCaptures: true,
                systemPromptFragments: [Self.voiceStylePrompt, Self.teachPrompt, Self.pointingPrompt]
            )
        case .askBeforeAct:
            return TurnPolicy(
                mode: mode,
                sessionKey: "wingman-main",
                attachScreenCaptures: true,
                systemPromptFragments: [Self.voiceStylePrompt, Self.askBeforeActPrompt, Self.pointingPrompt]
            )
        case .act:
            return TurnPolicy(
                mode: mode,
                sessionKey: "wingman-main",
                attachScreenCaptures: true,
                systemPromptFragments: [Self.voiceStylePrompt, Self.actPrompt, Self.pointingPrompt]
            )
        }
    }
}
