# Maverick — Remote Terminal Access (iOS ↔ macOS)

A two-app system that lets you run and control persistent terminal sessions on your Mac from an iPhone over Tailscale.

- **MaverickAgent** — macOS menu bar daemon that hosts pty sessions and exposes them over WebSocket.
- **MaverickRemote** — iOS app with a SwiftTerm-powered terminal view and a session-switcher sidebar.
- **MaverickProtocol** — shared Swift Package defining the Codable message types both apps use.

Use case: keep long-running CLI tools (Claude Code, Codex, etc.) running on your Mac and interact with them from your phone.

## Getting Started

### Prerequisites

- macOS with Xcode 15 or newer
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — install with `brew install xcodegen`
- [Tailscale](https://tailscale.com) installed on both your Mac and iPhone (for connection beyond the local network)

### Generate the Xcode project

This project uses `project.yml` as the source of truth for the Xcode project. `Maverick.xcodeproj` is generated and not committed.

```bash
xcodegen generate
```

Run this whenever `project.yml` changes, or after a fresh clone.

### Build and run

Open `Maverick.xcodeproj` in Xcode. Two schemes are available:

- `MaverickAgent` — run on your Mac. It appears in the menu bar.
- `MaverickRemote` — run on an iOS simulator or device.

## Project Layout

```
shared/             MaverickProtocol Swift Package (Codable message types)
server/             MaverickAgent source (macOS menu bar app)
client/             MaverickRemote source (iOS app)
docs/superpowers/   Spec and implementation plan
project.yml         xcodegen project spec
```

## Documentation

- Spec: `docs/superpowers/specs/2026-05-27-maverick-terminal-remote-design.md`
- Implementation plan: `docs/superpowers/plans/2026-05-27-maverick-terminal-remote.md`
