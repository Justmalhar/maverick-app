# Maverick — Remote Terminal Access (iOS ↔ Mac)

**Date:** 2026-05-27  
**Status:** Approved  
**Stack:** Swift (macOS + iOS), Network.framework, SwiftTerm, Tailscale  

---

## Overview

Two native Swift apps — a macOS menu bar daemon (`MaverickAgent`) and an iOS app (`MaverickRemote`) — connected over Tailscale via a WebSocket protocol. The Mac creates and manages persistent pty sessions (shells, Claude Code, Codex, etc.). The iOS app renders them as full terminal views with a session-switcher sidebar. Sessions outlive phone disconnects; reconnecting replays the scrollback buffer.

---

## Architecture

```
MaverickAgent    →  macOS menu bar app (daemon)
MaverickRemote   →  iOS app
MaverickProtocol →  Swift Package (shared Codable message types)
```

Data flow:
```
[iOS SwiftTerm view]
       ↕ URLSessionWebSocketTask
  [Tailscale mesh / WireGuard]
       ↕ NWListener WebSocket server (port 8765)
[Mac SessionManager + PTYSession]
       ↕ posix pty (forkpty)
  [shell / claude code / codex / any CLI]
```

---

## WebSocket Protocol

All messages are JSON. Terminal data is base64-encoded raw pty bytes to preserve escape sequences.

### Client → Server

| Message | Fields |
|---|---|
| `list_sessions` | — |
| `create_session` | `name: String`, `shell: String` (default `/bin/zsh`) |
| `attach_session` | `sessionId: UUID` |
| `input` | `sessionId: UUID`, `data: String` (base64) |
| `resize` | `sessionId: UUID`, `cols: Int`, `rows: Int` |
| `close_session` | `sessionId: UUID` |

### Server → Client

| Message | Fields |
|---|---|
| `session_list` | `sessions: [SessionInfo]` |
| `session_created` | `session: SessionInfo` |
| `output` | `sessionId: UUID`, `data: String` (base64) |
| `scrollback` | `sessionId: UUID`, `data: String` (base64, full buffer replay) |
| `session_closed` | `sessionId: UUID` |
| `error` | `message: String` |

### Auth

Optional shared token passed as WebSocket URL query parameter:  
`ws://my-macbook.tail12345.ts.net:8765/ws?token=<token>`  
Token is generated in Mac app preferences and stored once in iOS app (Keychain). Server closes connection with code `4401` on mismatch.

---

## Mac Daemon (`MaverickAgent`)

### File Structure

```
MaverickAgent/
  AppDelegate.swift              — NSApplication entry, menu bar setup
  MenuBarController.swift        — status item, popover with server controls
  SessionManager.swift           — Swift actor, owns all PTYSession instances
  PTYSession.swift               — forkpty + Process + scrollback ring buffer
  WebSocketServer.swift          — NWListener, accepts NWConnection per client
  ClientHandler.swift            — per-connection message parsing + routing
  Protocol.swift                 — Codable structs (shared with MaverickProtocol pkg)
```

### `PTYSession`

- Calls `forkpty()` to obtain master fd + child pid
- Launches configurable shell (default `/bin/zsh`) in child process
- `DispatchSource.makeReadSource(fileDescriptor:)` reads pty output asynchronously
- Output appended to `CircularBuffer<UInt8>` capped at ~10k lines (~1MB)
- Output broadcast to all `ClientHandler`s attached to this session

### `SessionManager`

- Swift `actor` for thread-safe access
- `var sessions: [UUID: PTYSession]`
- Notifies all connected clients on session list changes

### `WebSocketServer`

- `NWListener` on TCP port 8765 with `.webSocket` protocol framing
- Each accepted connection creates a `ClientHandler`
- Token validation at handshake via URL query parameters

### `MenuBarController`

- Status icon shows connected client count as badge
- Popover: server on/off, port config, token display/regenerate, active session list
- First launch: requests permission to install `launchd` plist for auto-start on login

---

## iOS App (`MaverickRemote`)

### File Structure

```
MaverickRemote/
  App/
    MaverickRemoteApp.swift
    ContentView.swift                 — NavigationSplitView root
  Features/
    Connection/
      ConnectionView.swift            — host/port/token entry, connect button
      ConnectionManager.swift         — URLSessionWebSocketTask, reconnect logic
    Sessions/
      SessionListView.swift           — sidebar: list, + new, swipe-to-close
      SessionStore.swift              — @Observable, source of truth
    Terminal/
      TerminalContainerView.swift     — SwiftUI → UIKit bridge
      TerminalViewController.swift    — UIViewControllerRepresentable, hosts SwiftTerm
      InputToolbar.swift              — Ctrl, Esc, Tab, arrow keys toolbar
  Shared/
    Extensions/
      Data+Base64.swift
```

### `ConnectionManager` (`@Observable`)

- Stores last-used host in `UserDefaults`, token in Keychain
- Auto-reconnects with exponential backoff (1s → 2s → 4s → max 30s)
- Publishes `connectionState: .disconnected | .connecting | .connected`

### `SessionStore` (`@Observable`)

- Receives `session_list` / `session_created` / `session_closed` → updates `[Session]`
- Routes `output` and `scrollback` bytes to the correct `TerminalViewController`
- Tracks `activeSessionId`

### `TerminalViewController`

- Hosts `SwiftTerm.TerminalView` (UIKit view)
- `scrollback` message: feeds bytes then marks replay boundary
- `output` message: feeds raw bytes directly (SwiftTerm handles all ANSI/VT escape codes)
- On view resize: calculates col/row count from view bounds, sends `resize` message

### `InputToolbar`

Sticky bar rendered above the software keyboard:  
`Ctrl` (latch modifier) · `Esc` · `Tab` · `↑` `↓` `←` `→` · `Ctrl+C`  
`Ctrl` latches: tap once, next character sent as control code (e.g. Ctrl+C = `\x03`).

### Navigation

| Device | Layout |
|---|---|
| iPhone (compact) | Full-screen terminal; hamburger opens sheet-style session list |
| iPad / landscape | `NavigationSplitView` with persistent sidebar |

---

## Session Lifecycle

### Connect & create

1. iOS taps `+` → `create_session`
2. Mac: `forkpty()` + spawn shell → new `PTYSession`
3. Mac: sends `session_created` + updated `session_list`
4. iOS: auto-attaches → Mac sends `scrollback` (empty) → live streaming begins

### Phone disconnect & reconnect

1. iOS backgrounds or locks → WebSocket drops
2. Mac: `ClientHandler` sees connection cancelled; `PTYSession` keeps running
3. iOS foregrounds → `ConnectionManager` reconnects with backoff
4. iOS sends `attach_session` for last active session
5. Mac sends full `scrollback` replay → live streaming resumes

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Daemon unreachable | `ConnectionView` shows error + retry |
| Mid-session disconnect | Auto-reconnect; terminal shows `[reconnecting…]` overlay |
| Session process exits | Mac sends `session_closed`; iOS removes from list, shows toast |
| Token mismatch | Server closes with code 4401; iOS shows auth error |
| Pty write error | Mac sends `error` message; iOS shows inline error |
| Port already in use | Mac logs error; menu bar icon shows warning badge |
| Mac reboot | Sessions lost (expected); daemon auto-restarts via launchd |

---

## Testing

### Unit tests

- `PTYSessionTests` — create session, write input, verify output accumulates in scrollback
- `CircularBufferTests` — ring buffer overflow, correct eviction at cap
- `ProtocolTests` — encode/decode all message types; malformed JSON handling
- `SessionManagerTests` — concurrent create/destroy via actor isolation

### Integration tests

- `WebSocketServerTests` — ephemeral port, test client connects, creates session, verifies output roundtrip
- `ReconnectTests` — simulate disconnect, reconnect, verify scrollback replay correctness

### Manual checklist

- [ ] Claude Code running on Mac, controlled entirely from iPhone
- [ ] Session survives phone screen lock + unlock (scrollback replay correct)
- [ ] Ctrl+C kills a running process
- [ ] Rotate iPhone: terminal reflows to new dimensions
- [ ] Create 5 sessions, switch between them, verify independent state
- [ ] Mac reboot: daemon restarts via launchd, iOS reconnects cleanly

### Out of scope

- Multiple simultaneous iOS clients (architecture supports it, not a priority)
- Non-zsh shells explicitly tested (fish/bash should work)

---

## Package Dependencies

| Package | Purpose |
|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | Terminal emulator view (iOS) |
| Network.framework | WebSocket server (Mac, system framework) |
| Foundation | URLSessionWebSocketTask (iOS, system framework) |

No third-party dependencies on the Mac daemon side.

---

## Out of Scope (v1)

- Android / Windows client
- File transfer (sftp)
- Port forwarding / tunneling through the app
- Custom themes per session
- Session sharing between multiple users
