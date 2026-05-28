# Maverick — Backlog

Items consciously deferred. Not bugs; future work.

## D. Aggressive folder picker cache prefetch

**Current state:** When the user opens the folder picker, listings are
on-demand. Server caches each listing 10s; client caches up to 64 paths 30s.
First entry to a new directory still pays one WebSocket round-trip.

**Desired:** When a session is launched in `<cwd>`, the server should
pre-list `<cwd>` and its immediate child directories in the background and
push them as a single combined listing message. The iOS browser then opens
instantly even on first use.

**Implementation sketch:**
- New `prefetchListings(path:)` request on the protocol (or piggy-back on
  `index_chunk`)
- Server walks one level deep (don't go deeper — explodes), emits the
  parent + each immediate child's listing in a single `directory_listing_bulk`
  message
- Client `DirectoryBrowserModel` stores the bulk listing in its LRU
- Trigger: just after `sessionCreated` arrives for a session whose `cwd`
  is non-empty

Estimate: 2–3 hours. Low risk, high felt-snappiness.

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
