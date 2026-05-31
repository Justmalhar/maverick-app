# MaverickAgent — Deprecated (superseded by the Maverick IDE companion server)

> Status: **deprecated, kept one release as a fallback.** Do not add features here.

## What changed

`MaverickAgent` (this `server/` target) was the standalone macOS menu-bar daemon
that hosted PTY sessions and the agent-event/Claude-hook bridge over a WebSocket,
which `MaverickRemote` (the iOS app) connected to over Tailscale.

That role now lives **inside the Maverick desktop IDE** (`crynta/maverick`), in its
Rust core under `src-tauri/src/remote/`:

| MaverickAgent (here) | Maverick IDE replacement |
|---|---|
| `WebSocketServer` / `ClientHandler` | `remote/ws_server.rs` + `remote/connection.rs` (tokio-tungstenite, loopback by default) |
| `SessionManager` / `PTYSession` | the IDE's Rust `pty` module + the per-session **ring buffer** (`pty/ring.rs`, 1 MiB, 256 KiB replay-on-attach) |
| `AgentEventNormalizer` + the 5 adapters | `remote/adapters/*` (Claude rich-stream + Codex `--json` full; OpenCode/Antigravity/Hermes heuristic) |
| `HookServer` / `HookConfigWriter` | `remote/hook_server.rs` (localhost:7789, blocking PermissionRequest, idempotent `~/.claude/settings.json` merge) |
| `CircularBuffer` | `pty/ring.rs` |
| Git / directory / project / upload services | bridged to the IDE's existing git/file RPC via `remote/bridge.rs` |
| *(none — token was a no-op)* | **real auth**: X25519/Noise_XX QR pairing + per-device token gate + capability scope (`remote/pairing.rs`, `remote/auth*.rs`) |

The wire contract is unchanged: the IDE serves the exact same `MaverickProtocol`
(`shared/`), so the **iOS/RN client connects to the IDE with no protocol changes**
(point it at the IDE's `/ws` on the paired host).

## Why it's kept (for now)

This daemon remains, archived, as a one-release escape hatch: if a regression
surfaces in the IDE's companion server in the field, you can relaunch the old
daemon (same port/protocol) with zero client changes. **Caveat:** MaverickAgent has
**no auth and no persistence** — falling back to it means an unauthenticated,
in-memory server, acceptable only briefly on a trusted tailnet.

## Cutover checklist (remaining, live-verification)

- [ ] Validate the **unmodified** `MaverickRemote` app against the IDE server for the
      full feature surface (terminal, agent chat + Claude permissions, git, files,
      upload) — byte-for-byte contract parity is the correctness signal.
- [ ] Pair a device via QR over LAN; confirm `remote_start`/`remote_pair`/`remote_revoke`.
- [ ] Stop shipping/launching this menu-bar daemon once parity is confirmed.
- [ ] After one clean release, delete `server/`.

*Tracked under Companion-6 in the Maverick MASTER-PLAN.*
