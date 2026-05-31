/**
 * Port of `AgentEvent` from AgentEvent.swift.
 *
 * Discriminator is a snake_case `type` string sibling to flat payload keys.
 * Decode MUST throw on an unknown `type` (Swift throws
 * `DecodingError.dataCorrupted`). Note the non-obvious key choices preserved
 * from Swift:
 *   - tool_call_* wraps the ToolCallEvent under key `event`
 *   - tool_batch_complete wraps the array under key `events`
 *   - permission_request wraps the PermissionEvent under key `permissionEvent`
 *   - notification uses key `notificationType` (not `type`) for its enum
 *   - session_error / session_end carry the enum under key `reason`
 *   - raw_terminal_bytes carries base64 under key `data`
 */

import {
  AgentProvider,
  AGENT_PROVIDERS,
  BadgeKind,
  BADGE_KINDS,
  EffortLevel,
  EFFORT_LEVELS,
  isMember,
  NotificationType,
  NOTIFICATION_TYPES,
  SessionEndReason,
  SESSION_END_REASONS,
  SessionSource,
  SESSION_SOURCES,
  StopFailureReason,
  STOP_FAILURE_REASONS,
} from './enums';
import {
  asObject,
  decodeBase64,
  DecodeError,
  encodeBase64,
  JSONObject,
  optInt,
  optNumber,
  optString,
  reqArray,
  reqString,
} from './primitives';
import {
  decodeElicitationField,
  decodePermissionEvent,
  decodeToolCallEvent,
  ElicitationField,
  encodeElicitationField,
  encodePermissionEvent,
  encodeToolCallEvent,
  PermissionEvent,
  ToolCallEvent,
} from './structs';

export type AgentEvent =
  | {
      type: 'session_start';
      id: string;
      provider: AgentProvider;
      cwd: string;
      model?: string;
      source: SessionSource;
    }
  | { type: 'session_end'; reason: SessionEndReason }
  | { type: 'cwd_changed'; from: string; to: string }
  | { type: 'user_message'; text: string }
  | { type: 'token_delta'; text: string }
  | { type: 'assistant_message'; text: string }
  | { type: 'tool_call_start'; event: ToolCallEvent }
  | { type: 'tool_call_complete'; event: ToolCallEvent }
  | { type: 'tool_call_failed'; event: ToolCallEvent }
  | { type: 'tool_batch_complete'; events: ToolCallEvent[] }
  | { type: 'permission_request'; permissionEvent: PermissionEvent }
  | { type: 'permission_denied'; tool: string; reason: string }
  | {
      type: 'subagent_start';
      id: string;
      agentType: string;
      parentSessionId: string;
    }
  | { type: 'subagent_stop'; id: string; agentType: string }
  | { type: 'task_created'; id: string; title: string }
  | { type: 'task_completed'; id: string }
  | { type: 'compaction_started' }
  | { type: 'compaction_complete' }
  | { type: 'worktree_created'; name: string; branch: string }
  | { type: 'worktree_removed'; path: string }
  | { type: 'notification'; notificationType: NotificationType; message: string }
  | { type: 'status_badge'; text: string; kind: BadgeKind }
  | { type: 'session_error'; reason: StopFailureReason }
  | {
      type: 'turn_stop';
      cost?: number;
      inputTokens?: number;
      outputTokens?: number;
      effortLevel?: EffortLevel;
    }
  | { type: 'elicitation'; server: string; fields: ElicitationField[] }
  | { type: 'raw_terminal_bytes'; data: Uint8Array };

function reqEnum<T extends string>(
  o: JSONObject,
  key: string,
  values: readonly T[],
  label: string,
): T {
  const raw = o[key];
  if (!isMember(values, raw)) {
    throw new DecodeError(`Unknown ${label}: ${String(raw)}`);
  }
  return raw;
}

export function decodeAgentEvent(value: unknown): AgentEvent {
  const o = asObject(value);
  const type = o.type;
  if (typeof type !== 'string') {
    throw new DecodeError('AgentEvent is missing string "type"');
  }
  switch (type) {
    case 'session_start': {
      const ev: AgentEvent = {
        type,
        id: reqString(o, 'id'),
        provider: reqEnum(o, 'provider', AGENT_PROVIDERS, 'AgentProvider'),
        cwd: reqString(o, 'cwd'),
        source: reqEnum(o, 'source', SESSION_SOURCES, 'SessionSource'),
      };
      const model = optString(o, 'model');
      if (model !== undefined) ev.model = model;
      return ev;
    }
    case 'session_end':
      return {
        type,
        reason: reqEnum(o, 'reason', SESSION_END_REASONS, 'SessionEndReason'),
      };
    case 'cwd_changed':
      return { type, from: reqString(o, 'from'), to: reqString(o, 'to') };
    case 'user_message':
      return { type, text: reqString(o, 'text') };
    case 'token_delta':
      return { type, text: reqString(o, 'text') };
    case 'assistant_message':
      return { type, text: reqString(o, 'text') };
    case 'tool_call_start':
    case 'tool_call_complete':
    case 'tool_call_failed': {
      if (o.event === undefined) {
        throw new DecodeError(`${type} is missing field "event"`);
      }
      return { type, event: decodeToolCallEvent(o.event) };
    }
    case 'tool_batch_complete': {
      if (o.events === undefined) {
        throw new DecodeError('tool_batch_complete is missing field "events"');
      }
      return { type, events: reqArray(o, 'events').map(decodeToolCallEvent) };
    }
    case 'permission_request': {
      if (o.permissionEvent === undefined) {
        throw new DecodeError(
          'permission_request is missing field "permissionEvent"',
        );
      }
      return { type, permissionEvent: decodePermissionEvent(o.permissionEvent) };
    }
    case 'permission_denied':
      return { type, tool: reqString(o, 'tool'), reason: reqString(o, 'reason') };
    case 'subagent_start':
      return {
        type,
        id: reqString(o, 'id'),
        agentType: reqString(o, 'agentType'),
        parentSessionId: reqString(o, 'parentSessionId'),
      };
    case 'subagent_stop':
      return { type, id: reqString(o, 'id'), agentType: reqString(o, 'agentType') };
    case 'task_created':
      return { type, id: reqString(o, 'id'), title: reqString(o, 'title') };
    case 'task_completed':
      return { type, id: reqString(o, 'id') };
    case 'compaction_started':
      return { type };
    case 'compaction_complete':
      return { type };
    case 'worktree_created':
      return { type, name: reqString(o, 'name'), branch: reqString(o, 'branch') };
    case 'worktree_removed':
      return { type, path: reqString(o, 'path') };
    case 'notification':
      return {
        type,
        notificationType: reqEnum(
          o,
          'notificationType',
          NOTIFICATION_TYPES,
          'NotificationType',
        ),
        message: reqString(o, 'message'),
      };
    case 'status_badge':
      return {
        type,
        text: reqString(o, 'text'),
        kind: reqEnum(o, 'kind', BADGE_KINDS, 'BadgeKind'),
      };
    case 'session_error':
      return {
        type,
        reason: reqEnum(o, 'reason', STOP_FAILURE_REASONS, 'StopFailureReason'),
      };
    case 'turn_stop': {
      const ev: AgentEvent = { type };
      const cost = optNumber(o, 'cost');
      if (cost !== undefined) ev.cost = cost;
      const inputTokens = optInt(o, 'inputTokens');
      if (inputTokens !== undefined) ev.inputTokens = inputTokens;
      const outputTokens = optInt(o, 'outputTokens');
      if (outputTokens !== undefined) ev.outputTokens = outputTokens;
      const effortLevel = optString(o, 'effortLevel');
      if (effortLevel !== undefined) {
        if (!isMember(EFFORT_LEVELS, effortLevel)) {
          throw new DecodeError(`Unknown effortLevel: ${effortLevel}`);
        }
        ev.effortLevel = effortLevel;
      }
      return ev;
    }
    case 'elicitation':
      return {
        type,
        server: reqString(o, 'server'),
        fields: reqArray(o, 'fields').map(decodeElicitationField),
      };
    case 'raw_terminal_bytes':
      return { type, data: decodeBase64(o.data) };
    default:
      throw new DecodeError(`Unknown AgentEvent type: ${type}`);
  }
}

export function encodeAgentEvent(ev: AgentEvent): JSONObject {
  switch (ev.type) {
    case 'session_start': {
      const out: JSONObject = {
        type: ev.type,
        id: ev.id,
        provider: ev.provider,
        cwd: ev.cwd,
        source: ev.source,
      };
      if (ev.model !== undefined) out.model = ev.model;
      return out;
    }
    case 'session_end':
      return { type: ev.type, reason: ev.reason };
    case 'cwd_changed':
      return { type: ev.type, from: ev.from, to: ev.to };
    case 'user_message':
      return { type: ev.type, text: ev.text };
    case 'token_delta':
      return { type: ev.type, text: ev.text };
    case 'assistant_message':
      return { type: ev.type, text: ev.text };
    case 'tool_call_start':
      return { type: ev.type, event: encodeToolCallEvent(ev.event) };
    case 'tool_call_complete':
      return { type: ev.type, event: encodeToolCallEvent(ev.event) };
    case 'tool_call_failed':
      return { type: ev.type, event: encodeToolCallEvent(ev.event) };
    case 'tool_batch_complete':
      return { type: ev.type, events: ev.events.map(encodeToolCallEvent) };
    case 'permission_request':
      return {
        type: ev.type,
        permissionEvent: encodePermissionEvent(ev.permissionEvent),
      };
    case 'permission_denied':
      return { type: ev.type, tool: ev.tool, reason: ev.reason };
    case 'subagent_start':
      return {
        type: ev.type,
        id: ev.id,
        agentType: ev.agentType,
        parentSessionId: ev.parentSessionId,
      };
    case 'subagent_stop':
      return { type: ev.type, id: ev.id, agentType: ev.agentType };
    case 'task_created':
      return { type: ev.type, id: ev.id, title: ev.title };
    case 'task_completed':
      return { type: ev.type, id: ev.id };
    case 'compaction_started':
      return { type: ev.type };
    case 'compaction_complete':
      return { type: ev.type };
    case 'worktree_created':
      return { type: ev.type, name: ev.name, branch: ev.branch };
    case 'worktree_removed':
      return { type: ev.type, path: ev.path };
    case 'notification':
      return {
        type: ev.type,
        notificationType: ev.notificationType,
        message: ev.message,
      };
    case 'status_badge':
      return { type: ev.type, text: ev.text, kind: ev.kind };
    case 'session_error':
      return { type: ev.type, reason: ev.reason };
    case 'turn_stop': {
      const out: JSONObject = { type: ev.type };
      if (ev.cost !== undefined) out.cost = ev.cost;
      if (ev.inputTokens !== undefined) out.inputTokens = ev.inputTokens;
      if (ev.outputTokens !== undefined) out.outputTokens = ev.outputTokens;
      if (ev.effortLevel !== undefined) out.effortLevel = ev.effortLevel;
      return out;
    }
    case 'elicitation':
      return {
        type: ev.type,
        server: ev.server,
        fields: ev.fields.map(encodeElicitationField),
      };
    case 'raw_terminal_bytes':
      return { type: ev.type, data: encodeBase64(ev.data) };
  }
}
