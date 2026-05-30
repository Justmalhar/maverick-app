# Maverick Mobile — Agent Guide

Cross-platform React Native client for Maverick (ADR-3). One Expo + expo-router
+ react-native-web codebase targets iOS / Android / web. Goal: "laptop =
server, anything = client."

## Expo HAS CHANGED

Read the exact versioned docs at https://docs.expo.dev/versions/v56.0.0/ before
writing any RN/Expo code. This project is SDK 56 / RN 0.85 / React 19.

## Hard rules

1. **bun, not npm.** `bun install`, `bun run test`.
2. **The Swift `client/`, `server/`, `shared/` dirs are the conformance
   reference. Never modify them from here.** `shared/Sources/MaverickProtocol`
   is the source of truth for the wire protocol.
3. **`src/protocol` must stay byte-compatible with the Swift `MaverickProtocol`
   package.** When a Swift type changes, mirror it here and update the codec
   round-trip tests. The wire contract is:
   - snake_case `type` discriminator, flat *sibling* keys (NOT a nested payload)
   - all other field keys are camelCase (Swift JSONEncoder default key strategy)
   - dates: ISO8601, second precision, trailing `Z`
   - UUIDs: UPPERCASE hyphenated (Swift `uuidString`); decode is case-insensitive
   - binary (`raw_terminal_bytes`, upload `data`): standard base64
   - `AgentEvent` decode THROWS on an unknown `type`
   - `ToolKind` round-trips unknown tools through `custom(name)` as a bare string
4. **No API keys.** Pairing uses Noise; credentials never leave the desktop.

## Layout

```
mobile/
  app/                 expo-router routes (UI shell; UI lands in RN-2)
  src/
    protocol/          TS port of MaverickProtocol (enums, structs, codecs)
    net/               ConnectionManager + TransportTier (LAN now; iroh/relay stubs)
    pairing/           QR parse + Noise_XX_25519_ChaChaPoly_SHA256 + TOFU pinning
```

## Protocol gotchas (non-obvious key names)

- `tool_call_start|complete|failed` wrap the `ToolCallEvent` under key `event`.
- `tool_batch_complete` wraps the array under key `events`.
- `permission_request` wraps its `PermissionEvent` under key `permissionEvent`.
- `notification` carries its enum under key `notificationType` (NOT `type`).
- `session_error` / `session_end` carry their enum under key `reason`.
- `GitStatus.branch` is encoded as an explicit JSON `null` when absent (Swift
  uses `encode`, not `encodeIfPresent`). Other optionals are omitted when absent.

## Net layer

`ConnectionManager` is transport-agnostic: it only talks to a `Transport`
(TransportTier). LAN ws:// is implemented; `IrohTransport` / `RelayTransport`
are stubs that throw until Companion-5. Adding a tier = a new factory, no manager
changes. Backoff / generation-id / reattach behaviour mirrors the Swift
`ConnectionManager`. Timers and the transport factory are injectable for tests.

## Pairing

`InitiatorPairingSession` drives the mobile (initiator) side of a Noise XX
handshake against the desktop (responder). It parses the
`maverick://pair/v1?k&e&t&r&n&f` QR payload, runs the three-message XX exchange,
asserts the handshake-learned static key matches the QR-advertised key, and pins
it via TOFU. Derived transport keys are transport-independent (work over any
tier). The camera QR-scan UI is RN-2.

## Testing

`bun run test` (jest-expo). Test files are `*.test.ts` siblings under `src/`.
The logic core has no UI dependency, so tests run pure. Keep coverage high; the
codec, state machine, and handshake are all exercised against representative
fixtures + a real two-party Noise handshake.
