/**
 * Port of `ToolKind` from AgentEvent.swift.
 *
 * On the wire a ToolKind is a *single JSON string* — the case name for known
 * tools (`"read"`, `"webFetch"`, …) or the raw tool name for unknowns. Swift
 * round-trips unknowns through `.custom(name)`; we do the same here, so an
 * unrecognised string decodes to `{ kind: 'custom', name }` and re-encodes to
 * exactly that string.
 */

export const KNOWN_TOOL_KINDS = [
  // File I/O
  'read',
  'write',
  'edit',
  'notebookEdit',
  // Search
  'glob',
  'grep',
  'lsp',
  // Shell
  'bash',
  'powerShell',
  'monitor',
  // Web
  'webFetch',
  'webSearch',
  // Agents / orchestration
  'agent',
  'skill',
  'sendMessage',
  // Task management
  'taskCreate',
  'taskUpdate',
  'taskGet',
  'taskList',
  'taskStop',
  'cronCreate',
  'cronDelete',
  'cronList',
  // Planning
  'enterPlanMode',
  'exitPlanMode',
  'askUserQuestion',
  // Git worktrees
  'enterWorktree',
  'exitWorktree',
  // MCP
  'listMcpResources',
  'readMcpResource',
  'waitForMcpServers',
  'toolSearch',
  // System / infra
  'pushNotification',
  'scheduleWakeup',
  'remoteTrigger',
  'shareOnboardingGuide',
] as const;

export type KnownToolKind = (typeof KNOWN_TOOL_KINDS)[number];

export type ToolKind =
  | { kind: KnownToolKind }
  | { kind: 'custom'; name: string };

const KNOWN_SET: ReadonlySet<string> = new Set(KNOWN_TOOL_KINDS);

/** Construct a known ToolKind. */
export function tool(kind: KnownToolKind): ToolKind {
  return { kind };
}

/** Construct an unknown / catch-all ToolKind. */
export function customTool(name: string): ToolKind {
  return { kind: 'custom', name };
}

/** Decode a wire string into a ToolKind, never throwing (unknown → custom). */
export function decodeToolKind(raw: unknown): ToolKind {
  if (typeof raw !== 'string') {
    throw new TypeError(`ToolKind must be a string, got ${typeof raw}`);
  }
  if (KNOWN_SET.has(raw)) {
    return { kind: raw as KnownToolKind };
  }
  return { kind: 'custom', name: raw };
}

/** Encode a ToolKind back to its single wire string. */
export function encodeToolKind(t: ToolKind): string {
  return t.kind === 'custom' ? t.name : t.kind;
}
