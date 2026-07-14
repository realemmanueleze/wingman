# Wingman Mobile (roadmap)

Phones do **not** embed a gateway. They pair with the user's gateway as OpenClaw **nodes** — the exact model OpenClaw's `apps/ios` and `apps/android` already implement — so the product keeps one identity and one memory everywhere.

## Shape

- **Connect**: same Gateway WebSocket, `role: node`, device identity + pairing approval, remote reachability via Tailscale/SSH tunnel (OpenClaw's documented remote setup).
- **Voice + chat**: push-to-talk turns against the same sessions (`wingman-teach` / `wingman-main`), so mode policy carries over unchanged.
- **Device capabilities**: node caps expose `camera.*`, `screen.record`, `location.get` — the mobile equivalent of the Mac's screen vision. "Look at this" on a phone = camera or screen share attachment on the turn.
- **Pointing**: no desktop overlay; the `[POINT]` contract degrades gracefully — targets render as annotated screenshots (drawn marker on the image) instead of a flying cursor.

## Phasing

1. **v1**: pair + voice/chat with mode picker (reuse `packages/wingman-core` contracts; SwiftUI / Kotlin shells modeled on OpenClaw's node apps).
2. **v2**: camera/screen-share turns with annotated-image pointing.
3. **v3**: push notifications for approvals — approve an "ask-before-act" action from the phone while away from the desk.
