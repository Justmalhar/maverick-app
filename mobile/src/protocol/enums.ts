/**
 * Faithful TS port of the simple enums in
 * shared/Sources/MaverickProtocol/AgentEvent.swift.
 *
 * Swift `enum X: String, Codable` encodes the *case name* verbatim (no
 * snake_case conversion), so e.g. `claudeCode` stays `claudeCode` on the wire.
 * These string-literal unions reproduce that exactly.
 */

export const AGENT_PROVIDERS = [
  'claudeCode',
  'codex',
  'antigravity',
  'opencode',
  'hermes',
] as const;
export type AgentProvider = (typeof AGENT_PROVIDERS)[number];

export const SESSION_MODES = ['terminal', 'chat'] as const;
export type SessionMode = (typeof SESSION_MODES)[number];

export const SESSION_SOURCES = ['startup', 'resume', 'clear', 'compact'] as const;
export type SessionSource = (typeof SESSION_SOURCES)[number];

export const SESSION_END_REASONS = [
  'clear',
  'resume',
  'logout',
  'promptExit',
  'other',
] as const;
export type SessionEndReason = (typeof SESSION_END_REASONS)[number];

export const STOP_FAILURE_REASONS = [
  'rateLimit',
  'authFailed',
  'billing',
  'serverError',
  'maxTokens',
  'unknown',
] as const;
export type StopFailureReason = (typeof STOP_FAILURE_REASONS)[number];

export const BADGE_KINDS = ['info', 'warning', 'error', 'success'] as const;
export type BadgeKind = (typeof BADGE_KINDS)[number];

export const NOTIFICATION_TYPES = [
  'permissionPrompt',
  'idlePrompt',
  'authSuccess',
  'elicitation',
] as const;
export type NotificationType = (typeof NOTIFICATION_TYPES)[number];

export const EFFORT_LEVELS = ['low', 'medium', 'high', 'xhigh', 'max'] as const;
export type EffortLevel = (typeof EFFORT_LEVELS)[number];

/** Generic guard used by the codec to validate a string against a known set. */
export function isMember<T extends string>(
  values: readonly T[],
  raw: unknown,
): raw is T {
  return typeof raw === 'string' && (values as readonly string[]).includes(raw);
}
