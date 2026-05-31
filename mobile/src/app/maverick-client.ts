/**
 * MaverickClient — the single object the UI talks to. It owns a
 * `ConnectionManager`, builds the canonical LAN URL (host/port/token), exposes
 * the connection state as an `Observable`, fans out incoming `ServerMessage`s
 * to the registered stores, and offers typed `send*` helpers (so screens never
 * hand-build `ClientMessage`s) plus a `requestId()` generator for the
 * correlated request/response surfaces (directory, index, git).
 *
 * It deliberately mirrors the Swift `ConnectionManager` façade the views use,
 * while delegating the socket lifecycle to the RN-1 core ConnectionManager.
 */

import {
  AgentProvider,
  ClientMessage,
  randomUUID,
  ServerMessage,
  SessionMode,
} from '@/protocol';
import {
  ConnectionManager,
  ConnectionState,
} from '@/net/connection-manager';
import { LanTransport, lanUrl } from '@/net/transports';
import { Emitter } from '@/net/emitter';

export interface ConnectTarget {
  host: string;
  port: number;
  token?: string;
}

/** Default ConnectionManager wired to the production LAN transport tier. */
export function defaultManager(): ConnectionManager {
  return new ConnectionManager({
    transportFactory: (url) => new LanTransport(url),
  });
}

export class MaverickClient {
  readonly manager: ConnectionManager;
  readonly messages: Emitter<ServerMessage>;
  readonly states: Emitter<ConnectionState>;

  private current: ConnectTarget | null = null;

  constructor(manager: ConnectionManager = defaultManager()) {
    this.manager = manager;
    this.messages = this.manager.messages;
    this.states = this.manager.states;
  }

  get state(): ConnectionState {
    return this.manager.state;
  }

  get lastError(): string | null {
    return this.manager.lastError;
  }

  get target(): ConnectTarget | null {
    return this.current;
  }

  connect(target: ConnectTarget): void {
    this.current = target;
    this.manager.connect(lanUrl(target.host, target.port, target.token ?? ''));
  }

  disconnect(): void {
    this.manager.disconnect();
  }

  /** Fresh UPPERCASE UUID for a correlated request/response exchange. */
  requestId(): string {
    return randomUUID();
  }

  send(message: ClientMessage): void {
    this.manager.send(message);
  }

  // --- typed convenience senders (mirror the Swift call sites) -------------

  listSessions(): void {
    this.send({ type: 'list_sessions' });
  }

  attach(sessionId: string): void {
    this.manager.attach(sessionId);
  }

  createSession(name: string, shell: string, cwd?: string): void {
    const msg: ClientMessage = { type: 'create_session', name, shell };
    if (cwd !== undefined && cwd.length > 0) msg.cwd = cwd;
    this.send(msg);
  }

  createAgentSession(
    name: string,
    provider: AgentProvider,
    cwd?: string,
  ): void {
    const msg: ClientMessage = { type: 'create_agent_session', name, provider };
    if (cwd !== undefined && cwd.length > 0) msg.cwd = cwd;
    this.send(msg);
  }

  closeSession(sessionId: string): void {
    this.send({ type: 'close_session', sessionId });
  }

  switchSessionMode(sessionId: string, mode: SessionMode): void {
    this.send({ type: 'switch_session_mode', sessionId, mode });
  }

  input(sessionId: string, data: string): void {
    this.send({ type: 'input', sessionId, data });
  }

  resize(sessionId: string, cols: number, rows: number): void {
    this.send({ type: 'resize', sessionId, cols, rows });
  }

  agentInput(sessionId: string, text: string): void {
    this.send({ type: 'agent_input', sessionId, text });
  }

  respondToPermission(
    sessionId: string,
    requestId: string,
    allowed: boolean,
  ): void {
    this.send({ type: 'permission_response', sessionId, requestId, allowed });
  }

  listDirectory(requestId: string, path?: string): void {
    const msg: ClientMessage = { type: 'list_directory', requestId };
    if (path !== undefined && path.length > 0) msg.path = path;
    this.send(msg);
  }

  indexProject(requestId: string, path: string, refresh: boolean): void {
    this.send({ type: 'index_project', requestId, path, refresh });
  }

  gitStatus(requestId: string, path: string): void {
    this.send({ type: 'git_status', requestId, path });
  }

  gitDiff(requestId: string, path: string, file: string, staged: boolean): void {
    this.send({ type: 'git_diff', requestId, path, file, staged });
  }
}
