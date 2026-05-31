/**
 * Presentation helpers for agent tool calls (port of the Swift `ToolKind`
 * display metadata + `ToolBatchRowView` summary). Keeps every label/derivation
 * out of the RN component so it is unit-tested here.
 */

import { KnownToolKind, ToolCallEvent, ToolKind } from '@/protocol';

const DISPLAY_NAMES: Record<KnownToolKind, string> = {
  read: 'Read',
  write: 'Write',
  edit: 'Edit',
  notebookEdit: 'Notebook',
  glob: 'Glob',
  grep: 'Grep',
  lsp: 'LSP',
  bash: 'Bash',
  powerShell: 'PowerShell',
  monitor: 'Monitor',
  webFetch: 'Fetch',
  webSearch: 'Search',
  agent: 'Agent',
  skill: 'Skill',
  sendMessage: 'Message',
  taskCreate: 'TaskCreate',
  taskUpdate: 'TaskUpdate',
  taskGet: 'TaskGet',
  taskList: 'TaskList',
  taskStop: 'TaskStop',
  cronCreate: 'CronCreate',
  cronDelete: 'CronDelete',
  cronList: 'CronList',
  enterPlanMode: 'Plan',
  exitPlanMode: 'ExitPlan',
  askUserQuestion: 'AskUser',
  enterWorktree: 'Worktree',
  exitWorktree: 'ExitWorktree',
  listMcpResources: 'MCP',
  readMcpResource: 'MCPRead',
  waitForMcpServers: 'MCPWait',
  toolSearch: 'ToolSearch',
  pushNotification: 'Notify',
  scheduleWakeup: 'Schedule',
  remoteTrigger: 'Trigger',
  shareOnboardingGuide: 'Share',
};

export function toolDisplayName(tool: ToolKind): string {
  return tool.kind === 'custom' ? tool.name : DISPLAY_NAMES[tool.kind];
}

/** Whether a tool call failed (carries an error). */
export function toolFailed(event: ToolCallEvent): boolean {
  return event.error !== undefined;
}

/** Last path component of a file path (for diff pills). */
export function baseName(path: string): string {
  const trimmed = path.replace(/\/+$/, '');
  const idx = trimmed.lastIndexOf('/');
  return idx >= 0 ? trimmed.slice(idx + 1) : trimmed;
}

/**
 * Collapsed-row summary for a tool batch, e.g. "Read, Bash +2" with a failure
 * count when any tool errored.
 */
export function batchSummary(events: ToolCallEvent[]): string {
  if (events.length === 0) return 'No tools';
  const names = events.map((e) => toolDisplayName(e.tool));
  const head = names.slice(0, 2).join(', ');
  const extra = names.length - Math.min(2, names.length);
  const failures = events.filter(toolFailed).length;
  let summary = extra > 0 ? `${head} +${extra}` : head;
  if (failures > 0) summary += ` · ${failures} failed`;
  return summary;
}
