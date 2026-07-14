# Wingman

One desktop product combining two inspirations:

- **OpenClaw** (vendored fork at `vendor/openclaw`) — the brain: an always-on agent gateway with tools, memory, channels, and model routing.
- **Clicky** (patterns reimplemented in `apps/macos`) — the face: a screen companion that sees your displays, talks, and points at UI.

Wingman is a macOS menu-bar app that embeds an OpenClaw Gateway as a supervised sidecar and layers a Clicky-style buddy cursor on top. Hold **⌃⌥** anywhere, speak, and the assistant sees your screen, answers out loud, and flies a pointer to the relevant UI. Switch modes to let it actually do the work through gateway tools.

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

**TCC warning:** permissions bind to signing identity + path. For permission testing, install to a stable path and sign with a real identity (`SIGN_IDENTITY="Developer ID Application: …" make app-release`). Ad-hoc builds re-prompt on every rebuild.

## Modes

| Mode | Session | Behavior |
|------|---------|----------|
| **Teach** | `wingman-teach` | Sees, explains, points. Tool policy denies everything server-side. |
| **Ask before acting** | `wingman-main` | Tools allowed; risky actions go through exec approvals. |
| **Act** | `wingman-main` | Full operator agent under gateway policy. |

The client only *selects* the session; the gateway enforces tool policy. See `docs/HARD-PROBLEMS.md`.

## One product, more platforms

The brain (Gateway) and the contracts (`packages/wingman-core`) are platform-neutral. Each platform is a shell:

- **macOS** — this app (capture + overlay + PTT + sidecar)
- **Windows** — tray app + same sidecar pattern; overlay later (`apps/windows/README.md`)
- **Mobile** — OpenClaw node role: pairing, voice, camera/screen share (`apps/mobile/README.md`)
