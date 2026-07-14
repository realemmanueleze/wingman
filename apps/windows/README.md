# Wingman for Windows (roadmap)

Same product, new shell. Nothing in the brain changes.

## Shape

- **Tray app** (WinUI 3 or Tauri shell) plays the role the menu bar plays on macOS.
- **Gateway sidecar**: identical pattern to macOS — bundled portable Node + `openclaw` staged into the install dir, supervised child process, per-install token, loopback WS. OpenClaw already documents Windows support and ships a Windows Hub companion to model after.
- **Shared contracts** from `packages/wingman-core` (protocol, `[POINT]`, turn policy) consumed directly by a TS/Tauri shell, or mirrored for a native one.

## Phasing

1. **v1 — tray + chat + hotkey**: global push-to-talk (RegisterHotKey / Raw Input), Windows Speech or cloud STT, screen capture via `Windows.Graphics.Capture`, turns to the gateway. No overlay yet — responses are spoken and shown in a flyout.
2. **v2 — overlay buddy**: layered click-through window (WS_EX_LAYERED | WS_EX_TRANSPARENT) with the same `[POINT]` mapping. Windows permissions are simpler than TCC (capture consent is per-session picker or app capability).

## Notes

- Packaging: MSIX gives clean install/update; the Node runtime rides inside the package like the macOS bundle.
- The teach/act session policy is identical — it lives in the gateway, not the shell.
