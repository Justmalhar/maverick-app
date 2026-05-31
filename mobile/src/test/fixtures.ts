/**
 * Test fixtures + a capturing fake MaverickClient. Excluded from coverage
 * collection (src/test/**). Keeps the store tests terse and consistent.
 */

import { MaverickClient } from '@/app/maverick-client';
import {
  AgentEvent,
  ClientMessage,
  PermissionEvent,
  ServerMessage,
  SessionInfo,
  ToolCallEvent,
  tool,
} from '@/protocol';

let counter = 0;
export function uuid(): string {
  counter++;
  const n = counter.toString(16).padStart(12, '0');
  return `00000000-0000-4000-8000-${n}`.toUpperCase();
}

export function sessionInfo(over: Partial<SessionInfo> = {}): SessionInfo {
  return {
    id: over.id ?? uuid(),
    name: over.name ?? 'session',
    shell: over.shell ?? '/bin/zsh',
    createdAt: over.createdAt ?? new Date('2026-05-31T00:00:00Z'),
    ...(over.agentProvider !== undefined
      ? { agentProvider: over.agentProvider }
      : {}),
    ...(over.sessionMode !== undefined ? { sessionMode: over.sessionMode } : {}),
  };
}

export function toolCall(over: Partial<ToolCallEvent> = {}): ToolCallEvent {
  return {
    id: over.id ?? uuid(),
    tool: over.tool ?? tool('bash'),
    inputSummary: over.inputSummary ?? 'ls',
    ...(over.result !== undefined ? { result: over.result } : {}),
    ...(over.error !== undefined ? { error: over.error } : {}),
    ...(over.fileDiffs !== undefined ? { fileDiffs: over.fileDiffs } : {}),
  };
}

export function permission(over: Partial<PermissionEvent> = {}): PermissionEvent {
  return {
    requestId: over.requestId ?? uuid(),
    tool: over.tool ?? 'bash',
    inputSummary: over.inputSummary ?? 'rm -rf /tmp/x',
    ...(over.ruleMatched !== undefined ? { ruleMatched: over.ruleMatched } : {}),
  };
}

export function agentEvent(
  sessionId: string,
  event: AgentEvent,
): ServerMessage {
  return { type: 'agent_event', sessionId, event };
}

/** Captures every ClientMessage sent and lets tests inject ServerMessages. */
export class FakeClient {
  readonly sent: ClientMessage[] = [];
  connectedState: 'disconnected' | 'connecting' | 'connected' = 'connected';
  private reqCounter = 0;

  get state(): 'disconnected' | 'connecting' | 'connected' {
    return this.connectedState;
  }

  requestId(): string {
    this.reqCounter++;
    return `req-${this.reqCounter}`;
  }

  send(message: ClientMessage): void {
    this.sent.push(message);
  }
  listSessions(): void {
    this.send({ type: 'list_sessions' });
  }
  attach(sessionId: string): void {
    this.send({ type: 'attach_session', sessionId });
  }
  switchSessionMode(sessionId: string, mode: 'terminal' | 'chat'): void {
    this.send({ type: 'switch_session_mode', sessionId, mode });
  }
  gitStatus(requestId: string, path: string): void {
    this.send({ type: 'git_status', requestId, path });
  }
  gitDiff(requestId: string, path: string, file: string, staged: boolean): void {
    this.send({ type: 'git_diff', requestId, path, file, staged });
  }
  indexProject(requestId: string, path: string, refresh: boolean): void {
    this.send({ type: 'index_project', requestId, path, refresh });
  }
  listDirectory(requestId: string, path?: string): void {
    const msg: ClientMessage = { type: 'list_directory', requestId };
    if (path !== undefined) msg.path = path;
    this.send(msg);
  }

  last(): ClientMessage {
    return this.sent[this.sent.length - 1]!;
  }

  asClient(): MaverickClient {
    return this as unknown as MaverickClient;
  }
}
