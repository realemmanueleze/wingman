# Wingman Architecture

## Principle

**One brain, many shells.** The OpenClaw Gateway is the product's brain: agent loop, tools, skills, memory, channels, model routing. Every platform ships a thin native shell that (a) supervises or attaches to a Gateway and (b) renders presence — overlay, tray, voice.

```
┌────────────────────────────── Wingman.app (macOS) ─────────────────────────────┐
│                                                                                │
│  Menu bar (SwiftUI)    Overlay (buddy cursor)     Push-to-talk (CGEvent tap)   │
│        │                      ▲                          │                     │
│        ▼                      │ [POINT] mapping          ▼                     │
│  AppModel ── ScreenCaptureService (SCK) ──► GatewayClient (WS, protocol v4)    │
│        │                                            │                          │
│        ▼                                            ▼                          │
│  GatewaySidecar ──spawns──► node openclaw gateway (127.0.0.1:18789, token)     │
│                                   │                                            │
└───────────────────────────────────┼────────────────────────────────────────────┘
                                    ▼
              agent loop · tools · memory · channels · providers
                     (WhatsApp/Telegram/… reach the same brain)
```

## Turn pipeline (macOS)

1. `PushToTalkMonitor` (listen-only CGEvent tap) fires on ⌃⌥ down → `SpeechService` starts local STT.
2. Key-up → transcript finalized → `ScreenCaptureService` snapshots all displays (own windows excluded, cursor screen first, ≤1280px JPEG).
3. `TurnPolicy.resolve(mode)` picks the gateway session + system prompt fragments.
4. `GatewayClient.runAgentTurn` sends the `agent` RPC: message + base64 image attachments + `extraSystemPrompt`. The ack returns a `runId`; assistant text streams via `agent` events; a second response with the same request id closes the run.
5. `PointTag.parse` strips `[POINT:x,y:label:screenN]`; coordinates map screenshot-pixels → display points → global AppKit point.
6. `SpeechService.speak` reads the answer; the overlay buddy flies to the target and shows the label, then returns to trailing the mouse.

## Contracts (in `packages/wingman-core`, mirrored in Swift)

- **Gateway protocol subset** — connect handshake (protocol v4, `gateway-client`/`ui` identity, token auth), req/res/event envelopes, agent params.
- **Pointing contract** — the `[POINT]` tag grammar and the prompt fragment that teaches it. Inherited from Clicky, now model-agnostic via the gateway.
- **Turn policy** — teach / ask-before-act / act, each bound to a gateway session whose tool policy is enforced server-side.

Swift mirrors: `TurnPolicy.swift`, `PointTag.swift`. The TS files are canonical; keep them in sync.

## Platform strategy

| Platform | Shell | Gateway | Presence |
|----------|-------|---------|----------|
| macOS | Swift (this app) | embedded sidecar or attach | overlay buddy + voice + menu bar |
| Windows | tray app (native or Tauri) | same sidecar pattern (Node bundled) | tray + chat window first; overlay v2 |
| iOS/Android | OpenClaw **node** role apps | remote (their Mac/PC or server) | voice/chat, camera, screen share via node caps |
| Everywhere else | none needed | — | channels (WhatsApp, Telegram, …) already reach the brain |

Mobile does not embed a gateway: phones pair with the user's gateway as nodes — exactly OpenClaw's existing `apps/ios` / `apps/android` model — so memory and identity stay singular.
