# Maverick — Backlog

Items consciously deferred. Not bugs; future work.

## D. Aggressive folder picker cache prefetch — IN PROGRESS

**Phase 1 (shipped):** Eager warmup of $HOME + its immediate children at
agent startup. Background prefetch of subdirectories on every list call.
30s background refresh loop. iOS preflights $HOME the moment the
WebSocket reaches .connected.

**Phase 2 (this is what's left):** FSEvents-based real-time invalidation.

Instead of the 30s polling loop, register an FSEventStream on the home
directory tree (or the set of visited paths). On each event, invalidate
the affected directory's cache entry; lazy re-fetch on next access. This
gives sub-second freshness without the periodic re-scan cost.

**Implementation sketch:**
- Wrap `FSEventStreamCreate` / `FSEventStreamSetDispatchQueue` /
  `FSEventStreamStart` in a small `FSEventWatcher` class. C-interop via
  `Unmanaged.passUnretained(self).toOpaque()` for the context pointer.
- Use `kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer`
  for fine-grained events. Latency: 0.5s.
- Maintain a watched-paths set; reconfigure the stream whenever a new
  directory is cached.
- In the callback, parse paths and call `invalidate(parent(path))` on the
  directory listing service.

Estimate: 0.5 day. Removes the 30s background scan entirely and makes
the index feel mtime-accurate.

## E. Hooks-driven push notifications

**Current state:** No push. Agent activity not surfaced when iOS is
backgrounded.

**Desired:** Mac daemon writes a Claude Code `Notification` hook into
`~/.claude/settings.json` that POSTs to localhost:8765/hook. The agent
fans the event to connected iOS clients as a `notification` message; if
no client is connected, queue and deliver on next reconnect, plus fire
APNs if available.

Estimate: APNs path ~2 days incl. cert + Cloudflare Worker; in-app
notification path ~0.5 days.

## F. Chat-mode UI for Claude Code

**Current state:** Terminal mode only. Output is raw ANSI through SwiftTerm.

**Desired:** Toggle that launches `claude --output-format=stream-json` and
renders structured chat messages (user / assistant / tool-call cards) in
a native bubble UI. Only viable for Claude Code today (Anthropic exposes
a structured output mode); other agents would need similar adapters.

Estimate: ~1 week for Claude Code only.
