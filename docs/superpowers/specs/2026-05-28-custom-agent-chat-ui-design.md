# Custom Agent Chat UI — Design Spec
**Date:** 2026-05-28  
**Status:** Approved  
**Project:** Maverick App

---

## Overview

Add a native chat UI to Maverick that renders AI agent conversations as structured messages — tool calls, file diffs, permission dialogs, streaming text — instead of raw terminal output. Users toggle between terminal view and chat view per session. The system is provider-agnostic: Claude Code, Codex, and Antigravity all map to the same normalized event schema; only the per-provider adapter differs.

**Reference UX:** Conductor.build — collapsed tool batch summaries, inline diff pills, status badges, iMessage-style bubbles.

---

## 1. Architecture

```
iOS Client                Mac Server                        Agent CLI
──────────────            ─────────────────────────────     ──────────────────────────
AgentSessionView          AgentSession (mode-aware)
  ├─ TerminalView  ◄────  PTYSession (existing, unchanged)  claude (interactive PTY)
  └─ ChatView      ◄────  AgentEventBroadcaster             claude --output-format stream-json
                           │                                codex --json
                           ├─ AgentEventNormalizer           antigravity run
                           │   ├─ ClaudeCodeAdapter
                           │   ├─ CodexAdapter
                           │   └─ AntigravityAdapter
                           │
                           HookServer (HTTP :7789)  ◄──────  Claude Code hooks (settings.json)
                           │
                    WebSocketServer (existing)
```

### Mode switching

- **Terminal mode:** `claude` launched via PTY as today. Raw bytes flow to `TerminalView`.
- **Chat mode:** `claude --output-format stream-json --resume <sessionId>` launched as a `Process` (not PTY). stdout lines → `AgentEventNormalizer` → `AgentEventBroadcaster` → WebSocket → `ChatView`.
- Toggling sends `sessionStop` to the client, terminates the current process, re-spawns in new mode using `--resume`. Conversation history is preserved server-side by Claude Code (~1–2s restart).
- `HookServer` runs permanently on `:7789` regardless of mode and feeds into the same broadcast stream.

---

## 2. Common Event Schema (Shared Swift Package)

All providers normalize to `AgentEvent`. The iOS client is entirely unaware of which provider is active.

```swift
// Tool categories — drives icon + color in UI
enum ToolKind: Codable {
    // File I/O (blue, file icon)
    case read, write, edit, notebookEdit
    // Search (purple, search icon)
    case glob, grep, lsp
    // Shell (orange, terminal icon)
    case bash, powerShell, monitor
    // Web (teal, globe icon)
    case webFetch, webSearch
    // Agents / orchestration (green, robot icon)
    case agent, skill, sendMessage
    // Task management (yellow, checklist icon)
    case taskCreate, taskUpdate, taskGet, taskList, taskStop
    case cronCreate, cronDelete, cronList
    // Planning (gray, lightbulb)
    case enterPlanMode, exitPlanMode, askUserQuestion
    // Git worktrees (red, git icon)
    case enterWorktree, exitWorktree
    // MCP (indigo, plug icon)
    case listMcpResources, readMcpResource, waitForMcpServers, toolSearch
    // System / infra (gray, gear)
    case pushNotification, scheduleWakeup, remoteTrigger, shareOnboardingGuide
    // Unknown MCP tool or future built-in
    case custom(String)   // e.g. mcp__memory__create_entities
}

enum AgentEvent: Codable {
    // Session lifecycle
    case sessionStart(id: String, provider: AgentProvider, cwd: String,
                      model: String?, source: SessionSource)
    case sessionEnd(reason: SessionEndReason)
    case cwdChanged(from: String, to: String)

    // User / assistant turns
    case userMessage(text: String)
    case tokenDelta(text: String)
    case assistantMessage(text: String)

    // Tool call lifecycle
    case toolCallStart(ToolCallEvent)
    case toolCallComplete(ToolCallEvent)
    case toolCallFailed(ToolCallEvent)
    case toolBatchComplete([ToolCallEvent])

    // Permissions
    case permissionRequest(PermissionEvent)
    case permissionDenied(tool: String, reason: String)

    // Agent / subagent
    case subagentStart(id: String, agentType: String, parentSessionId: String)
    case subagentStop(id: String, agentType: String)

    // Task tracking
    case taskCreated(id: String, title: String)
    case taskCompleted(id: String)

    // Compaction
    case compactionStarted
    case compactionComplete

    // Worktrees
    case worktreeCreated(name: String, branch: String)
    case worktreeRemoved(path: String)

    // Status / notifications
    case notification(type: NotificationType, message: String)
    case statusBadge(text: String, kind: BadgeKind)
    case sessionError(StopFailureReason)

    // Turn complete (cost + token usage from stream-json `result` event)
    case turnStop(cost: Double?, inputTokens: Int?, outputTokens: Int?,
                  effortLevel: EffortLevel?)

    // MCP elicitation
    case elicitation(server: String, fields: [ElicitationField])

    // Pass-through for terminal view
    case rawTerminalBytes(Data)
}

struct ToolCallEvent: Codable {
    var id: String
    var tool: ToolKind
    var input: [String: AnyCodable]
    var result: String?
    var error: String?
    var durationMs: Int?
    var fileDiffs: [FileDiff]?     // Write/Edit: parsed from tool_result
    var effort: EffortLevel?
}

struct FileDiff: Codable {
    var path: String
    var added: Int
    var removed: Int
}

struct PermissionEvent: Codable {
    var id: String
    var tool: String
    var input: [String: AnyCodable]
    var ruleMatched: String?
}

struct ElicitationField: Codable {
    var name: String
    var type: String
    var description: String
    var required: Bool
}

// AnyCodable: use the AnyCodable package (Flight-School/AnyCodable) or a local shim
// to represent arbitrary JSON values in tool_input / tool_result payloads.

enum AgentProvider: String, Codable    { case claudeCode, codex, antigravity }
enum SessionMode: String, Codable      { case terminal, chat }
enum SessionSource: String, Codable    { case startup, resume, clear, compact }
enum SessionEndReason: String, Codable { case clear, resume, logout, promptExit, other }
enum StopFailureReason: String, Codable { case rateLimit, authFailed, billing,
                                                serverError, maxTokens, unknown }
enum BadgeKind: String, Codable        { case info, warning, error, success }
enum NotificationType: String, Codable { case permissionPrompt, idlePrompt,
                                               authSuccess, elicitation }
enum EffortLevel: String, Codable      { case low, medium, high, xhigh, max }
```

---

## 3. Mac Server Changes

### New files

| File | Responsibility |
|---|---|
| `HookServer.swift` | Lightweight HTTP server on `:7789`. Receives hook POSTs, deserializes JSON, forwards to normalizer. Holds `PermissionRequest` responses open until iOS client replies (30s timeout → auto-deny). |
| `AgentEventNormalizer.swift` | Protocol + per-provider structs. Two entry points: `normalize(streamLine:)` and `normalize(hookPayload:)`. |
| `ClaudeCodeAdapter.swift` | Maps stream-json lines + hook payloads → `AgentEvent`. |
| `CodexAdapter.swift` | Maps `codex --json` stdout → `AgentEvent`. |
| `AntigravityAdapter.swift` | Heuristic stdout line parsing → `AgentEvent`. Swap for structured output when available. |
| `AgentEventBroadcaster.swift` | Merges events from stream-json stdout + hook HTTP in arrival order. Serializes to JSON, sends over existing `WebSocketServer`. |

### Modified files

**`AgentSession.swift`** (wraps existing `PTYSession`):
- Adds `mode: SessionMode` and `provider: AgentProvider`
- In `.chat` mode: spawns provider CLI as `Process`, reads stdout line-by-line
- `switchMode(_:)`: sends `sessionStop` event, terminates process, re-spawns with `--resume <sessionId>`

**`main.swift`**: starts `HookServer` on launch alongside `WebSocketServer`.

### Hook configuration

Written to `~/.claude/settings.json` by the Mac server on first launch:

```json
{
  "hooks": {
    "PreToolUse":        [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "PostToolUse":       [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "PostToolUseFailure":[{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "PostToolBatch":     [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "PermissionRequest": [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 30 }] }],
    "PermissionDenied":  [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "Stop":              [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "SubagentStart":     [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "SubagentStop":      [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "SessionStart":      [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "Notification":      [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "TaskCreated":       [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }],
    "TaskCompleted":     [{ "hooks": [{ "type": "http", "url": "http://localhost:7789/hook", "timeout": 10 }] }]
  }
}
```

### Provider launch commands

| Provider | Command |
|---|---|
| `claudeCode` | `claude --output-format stream-json --resume <sessionId>` |
| `codex` | `codex --json` |
| `antigravity` | `antigravity run` (stdout heuristics) |

### ClaudeCodeAdapter mapping

| Source | Raw event | → `AgentEvent` |
|---|---|---|
| stream-json | `stream` + `text_delta` | `.tokenDelta` |
| stream-json | `assistant` message complete | `.assistantMessage` |
| stream-json | `result` | `.turnStop(cost:inputTokens:outputTokens:)` |
| hook | `PreToolUse` | `.toolCallStart` |
| hook | `PostToolUse` | `.toolCallComplete` (+ parse diffs for Write/Edit) |
| hook | `PostToolUseFailure` | `.toolCallFailed` |
| hook | `PostToolBatch` | `.toolBatchComplete` |
| hook | `PermissionRequest` | `.permissionRequest` |
| hook | `PermissionDenied` | `.permissionDenied` |
| hook | `Stop` | `.turnStop` (fallback if stream-json result not received) |
| hook | `SubagentStart` | `.subagentStart` |
| hook | `SubagentStop` | `.subagentStop` |
| hook | `SessionStart` | `.sessionStart` |
| hook | `Notification` | `.notification` |
| hook | `TaskCreated` | `.taskCreated` |
| hook | `TaskCompleted` | `.taskCompleted` |
| hook | `StopFailure` | `.sessionError` |
| hook | `PreCompact` | `.compactionStarted` |
| hook | `PostCompact` | `.compactionComplete` |
| hook | `WorktreeCreate` | `.worktreeCreated` |
| hook | `CwdChanged` | `.cwdChanged` |

---

## 4. iOS Client Changes

### View hierarchy

```
AgentSessionView
├── mode toggle pill ("Terminal" | "Chat")
├── TerminalView        (existing, unchanged)
└── ChatView
    ├── MessageListView (scrollable)
    │   ├── UserBubbleView
    │   ├── AssistantBubbleView   (isStreaming: Bool)
    │   ├── ToolBatchRowView      ("5 tool calls · 3 files changed", collapsible)
    │   │   └── ToolCallDetailView (per tool)
    │   │       ├── ToolIconView   (icon + color per ToolKind category)
    │   │       ├── ToolInputView  (command string or key-value)
    │   │       └── FileDiffPillsView  ([auth.ts +11 -3] [route.ts +52 -52])
    │   ├── SubagentCardView      (collapsible, agent type + status)
    │   ├── TaskProgressView      (task created/completed)
    │   ├── StatusBadgeView       (LOGGED IN · INTERRUPTED · RATE LIMITED)
    │   └── PermissionDialogView  (blocks input, Allow / Deny buttons)
    └── ChatInputView
        ├── TextEditor (multiline, grows to 5 lines)
        ├── Send button
        └── Mode badge ("Claude Code · Sonnet 4.6")
```

### State model

```swift
@Observable class AgentSessionStore {
    var messages: [ChatMessage] = []
    var streamingText: String = ""
    var activeToolBatch: [ToolCallEvent] = []
    var pendingPermission: PermissionEvent?    // non-nil blocks input
    var sessionMode: SessionMode = .terminal
    var provider: AgentProvider = .claudeCode
    var lastCost: Double?
    var lastTokens: (input: Int, output: Int)?
}

enum ChatMessage {
    case user(String)
    case assistant(String, isStreaming: Bool)
    case toolBatch([ToolCallEvent])
    case subagentActivity(id: String, agentType: String, isComplete: Bool)
    case statusBadge(String, BadgeKind)
    case permissionRequest(PermissionEvent)
    case sessionEvent(String)    // cwd change, compaction, worktree, etc.
}
```

### Rendering rules

- `tokenDelta` appends to `streamingText`, updates last `.assistant(_, isStreaming: true)` message in-place — no new row per token.
- On `assistantMessage` (complete), `streamingText` clears, message transitions to `isStreaming: false`.
- Tool calls accumulate in `activeToolBatch` between `toolCallStart` and `toolBatchComplete`, then land as a single `ToolBatchRowView`.
- `permissionRequest` inserts `PermissionDialogView`, disables `ChatInputView` until user taps Allow or Deny. Response sent back to Mac server over WebSocket → forwarded as HTTP reply to the waiting hook.
- Mode toggle → WebSocket message to server → process restart with `--resume`.

### New files

| File | Responsibility |
|---|---|
| `ChatView.swift` | Top-level chat layout, subscribes to `AgentSessionStore` |
| `MessageListView.swift` | Scrollable message list, scroll-to-bottom on new events |
| `UserBubbleView.swift` | User message bubble |
| `AssistantBubbleView.swift` | Assistant message, streaming cursor while `isStreaming` |
| `ToolBatchRowView.swift` | Collapsed batch summary + expandable detail |
| `ToolCallDetailView.swift` | Per-tool icon, input, diff pills |
| `FileDiffPillsView.swift` | +green/-red pill per changed file |
| `PermissionDialogView.swift` | Allow / Deny overlay, 30s countdown |
| `SubagentCardView.swift` | Nested agent activity card |
| `ChatInputView.swift` | Multiline input, send, mode badge |
| `AgentSessionStore.swift` | Observable state, WebSocket event dispatch |

### Modified files

**`AgentSessionView.swift`**: adds mode toggle pill, conditionally shows `TerminalView` or `ChatView`.

---

## 5. Provider Adapters

| Provider | Output format | Hook support | Permission events |
|---|---|---|---|
| Claude Code | `--output-format stream-json` + HTTP hooks | Full (18+ events) | `PermissionRequest` hook → native dialog |
| Codex | `codex --json` stdout | None | Static `.statusBadge("Auto-approved", .info)` |
| Antigravity | Heuristic stdout line parsing | None | None |

Adding a new provider = one new adapter struct conforming to `AgentEventNormalizing`. No iOS client changes required.

---

## 6. Key Constraints & Decisions

- **No Agent SDK** — uses Claude subscription auth via CLI, not API keys.
- **Hook-based** for tool events + metadata; **stream-json** for token streaming. Both feed the same broadcaster.
- **`--resume`** preserves conversation history across mode switches. ~1–2s restart is acceptable for a deliberate toggle.
- **Permission request timeout:** 30 seconds. Server auto-denies if iOS client does not respond (e.g., app backgrounded).
- **Hook config auto-written** to `~/.claude/settings.json` on first Mac server launch. Existing hook entries are merged, not overwritten.
- **HookServer port 7789** is localhost-only. No external exposure.

---

## Build Sequence

1. `shared/` — Add `AgentEvent`, `ToolKind`, `ToolCallEvent`, supporting types to shared Swift package
2. `server/` — `HookServer`, `AgentEventNormalizer` protocol, `ClaudeCodeAdapter`, `AgentEventBroadcaster`, update `AgentSession` for mode-awareness
3. `server/` — `CodexAdapter`, `AntigravityAdapter`
4. `client/` — `AgentSessionStore`, `ChatView` + all sub-views
5. `client/` — Wire mode toggle in `AgentSessionView`
6. `server/` — Hook config auto-write on startup
7. Integration test: Claude Code session in chat mode, verify token streaming + tool batch rendering + permission dialog round-trip
