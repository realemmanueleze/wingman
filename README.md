# Wingman

**A voice-first AI copilot for macOS.** Hold **⌃⌥** anywhere and talk — Wingman sees your screen, answers out loud, flies a pointer to the relevant UI, and can run real tasks on your machine through a full agent gateway.

It pairs two halves into one double-clickable app:

- **The brain** — a vendored **OpenClaw** fork (`vendor/openclaw`) runs as a supervised sidecar: an always-on agent gateway with tools, memory, channels, and model routing.
- **The face** — a native Swift menu-bar app (`apps/macos`) that captures your displays, listens, speaks, and points, with a screen-native buddy cursor.

## Highlights

- **Push-to-talk, anywhere** — a global ⌃⌥ hotkey (system-wide event tap) starts listening in any app; release to send.
- **Streaming speech** — replies are spoken sentence-by-sentence as the model streams, so answers begin almost instantly instead of after the full response.
- **On-device speech** — recognition runs locally (fast, offline, private) and TTS auto-selects the best installed system voice.
- **Living top bar** — a slim "halo" line rests at the top-center of the screen and glows with voice activity; hover it and it expands into a command deck with mode controls and a session-history browser.
- **Voice indicator** — an animated waveform at the bottom-center reflects listening / thinking / speaking.
- **Voice commands** — app control ("act mode", "open chat", "stop talking") is handled locally with zero round-trip.
- **Adaptive speed** — easy conversational turns skip the model's reasoning phase; real work keeps full depth.
- **Points at UI** — the assistant can fly a cursor to a specific on-screen element via the `[POINT]` contract.

## Layout

| Path | What |
|------|------|
| `apps/macos/` | Native Swift app (SPM package): menu bar, overlay, capture, PTT, gateway sidecar + client |
| `packages/wingman-core/` | Shared cross-platform core: gateway protocol subset, `[POINT]` contract, teach/act turn policy (canonical reference for all shells) |
| `apps/windows/`, `apps/mobile/` | Platform roadmaps — same brain, new shells |
| `scripts/` | `make-app.sh` (assemble Wingman.app), `bundle-gateway.sh` (stage Node + openclaw into the bundle) |
| `docs/` | `ARCHITECTURE.md`, `HARD-PROBLEMS.md` |
| `vendor/openclaw/` | Our OpenClaw fork (source-only; builds ship inside the app) |

## For non-technical users

Open `Wingman.app`. A setup wizard runs on first launch:

1. **Welcome** — what Wingman is
2. **Permissions** — approve Screen Recording, Microphone/Speech, Accessibility with one click each
3. **Connect your AI** — pick Anthropic or OpenAI, paste an API key (link to the right console page is in the wizard); Wingman writes the OpenClaw config and restarts the gateway itself
4. **Try it** — hold ⌃⌥ and talk

No terminal at any point. The chat window (menu bar → **Open chat**) is the Claude-style work surface on the same brain; the buddy cursor is the screen-native surface.

## Our OpenClaw fork

`vendor/openclaw/` is our fork baseline, committed to this repo (runtime + plugins + UI, pruned of upstream docs/tests/CI). We self-improve it from here and ship it inside the app:

```bash
make gateway-bundle-fork   # build OUR fork and stage it into the app bundle
make app                   # → dist/Wingman.app with our gateway inside
```

To pull in a newer upstream release, download/clone it and refresh the baseline, then review the diff and commit:

```bash
make vendor-openclaw SRC=/path/to/downloaded/openclaw-main
```

`make gateway-bundle` still exists to bundle stock openclaw from npm instead.

## Quick start (development)

```bash
# 1. Compile
make build

# 2. Run against a gateway you already have (any of):
WINGMAN_GATEWAY_CMD="node /path/to/openclaw/openclaw.mjs gateway" make run
#    …or just have `openclaw gateway` already running — Wingman attaches to 127.0.0.1:18789.

# 3. Or package a launchable app
make app          # → dist/Wingman.app (ad-hoc signed, attaches to a running gateway)

# 4. Fully self-contained app (bundles Node + openclaw)
make gateway-bundle && make app
```

First launch walks through permissions in the menu-bar panel: Screen Recording, Microphone, Accessibility (hotkey), Speech Recognition.

**TCC warning:** permissions bind to signing identity + path. Ad-hoc builds generate a fresh signature on every rebuild, so macOS re-prompts (or silently drops) permissions each time. `make-app.sh` automatically uses a stable **"Wingman Dev"** self-signed identity if one exists in your keychain — create it once (Keychain Access → *Create a Certificate…*, type *Code Signing*) so Screen Recording / Microphone / Accessibility grants stick across rebuilds. Override with `SIGN_IDENTITY="Developer ID Application: …" make app` for release signing.

## Modes

| Mode | Session | Behavior |
|------|---------|----------|
| **Teach** | `wingman-teach` | Sees, explains, points. Tool policy denies everything server-side. |
| **Ask before acting** | `wingman-main` | Tools allowed; risky actions go through exec approvals. |
| **Act** | `wingman-main` | Full operator agent under gateway policy. |

The client only *selects* the session; the gateway enforces tool policy. See `docs/HARD-PROBLEMS.md`.

## Voice commands

Short spoken phrases are handled on-device (no gateway round-trip) — say them while holding ⌃⌥:

| Say | Does |
|-----|------|
| "act mode" / "teach mode" / "ask before acting" | Switch mode |
| "open chat" / "close chat" | Toggle the chat window |
| "show buddy" / "hide buddy" | Toggle the buddy cursor |
| "stop talking" | Cut off speech immediately |

Anything longer or unrecognized is sent to the agent as a normal request.

## Voice quality

Wingman automatically uses the best-quality voice installed on your Mac. The default system voices are robotic; for a natural voice, install a **Premium** one (free, one-time):

**System Settings → Accessibility → Spoken Content → System Voice → Manage Voices…**, then download e.g. *Ava (Premium)* under English. Restart Wingman and it's picked up automatically.

## One product, more platforms

The brain (Gateway) and the contracts (`packages/wingman-core`) are platform-neutral. Each platform is a shell:

- **macOS** — this app (capture + overlay + PTT + sidecar)
- **Windows** — tray app + same sidecar pattern; overlay later (`apps/windows/README.md`)
- **Mobile** — OpenClaw node role: pairing, voice, camera/screen share (`apps/mobile/README.md`)
