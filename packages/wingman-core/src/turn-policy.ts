/**
 * Teach-vs-act safety policy.
 *
 * The single most dangerous seam in the combined product: a casual "where is
 * the export button?" must never run shell commands, while "export it for me"
 * should. Policy is decided per turn on the client, and enforced server-side
 * by the gateway's session tool policy — the client mapping here only selects
 * which pre-configured gateway agent/session (with matching tool policy) the
 * turn is routed to. The gateway remains the source of truth.
 */

export type TurnMode = "teach" | "ask-before-act" | "act";

export type TurnPolicy = {
  mode: TurnMode;
  /** Gateway session key the turn is routed to. Tool policy is bound server-side per session. */
  sessionKey: string;
  /** Whether the shell should attach screen captures to this turn. */
  attachScreenCaptures: boolean;
  /** Extra system prompt fragments applied to this turn. */
  systemPromptFragments: string[];
};

export const TEACH_PROMPT = `
you are in TEACH mode. you can see the user's screen and explain and point, but you cannot run tools, execute commands, or modify anything. if the user asks you to perform an action, tell them to say "do it" (or switch to act mode) and describe exactly what you would do.
`.trim();

export const ASK_BEFORE_ACT_PROMPT = `
you are in ASK-BEFORE-ACT mode. you may use tools, but before any action that writes, deletes, sends, installs, or spends, state the exact action in one sentence and wait for approval through the exec approval flow.
`.trim();

/**
 * Session keys are stable per mode so the gateway can bind a tool policy to
 * each: `wingman-teach` denies all tools; `wingman-main` allows the operator
 * tool set with exec approvals per its configuration.
 */
export function resolveTurnPolicy(mode: TurnMode, pointingPrompt: string): TurnPolicy {
  switch (mode) {
    case "teach":
      return {
        mode,
        sessionKey: "wingman-teach",
        attachScreenCaptures: true,
        systemPromptFragments: [TEACH_PROMPT, pointingPrompt],
      };
    case "ask-before-act":
      return {
        mode,
        sessionKey: "wingman-main",
        attachScreenCaptures: true,
        systemPromptFragments: [ASK_BEFORE_ACT_PROMPT, pointingPrompt],
      };
    case "act":
      return {
        mode,
        sessionKey: "wingman-main",
        attachScreenCaptures: true,
        systemPromptFragments: [pointingPrompt],
      };
    default: {
      const exhaustive: never = mode;
      throw new Error(`Unhandled turn mode: ${String(exhaustive)}`);
    }
  }
}

/**
 * Gateway-side tool policy that must be present in openclaw.json for the
 * teach session. Kept here as the canonical reference so all shells and the
 * config bootstrapper agree.
 */
export const TEACH_SESSION_TOOL_POLICY = {
  sessionKey: "wingman-teach",
  tools: { deny: ["*"] },
} as const;
