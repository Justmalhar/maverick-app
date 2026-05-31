/**
 * Port of the Swift `SessionStore`. Tracks the live session list, the active
 * session, per-session live cwd (OSC-7), and routes terminal `output` /
 * `scrollback` frames to a registered per-session handler.
 *
 * Wire note: the protocol carries terminal bytes as a base64 string under
 * `data` (Swift decodes via `Data(base64Encoded:)`). The codec leaves it as a
 * string; the terminal buffer decodes it. We forward the raw string here.
 */

import { Observable } from '@/lib/observable';
import { ServerMessage, SessionInfo } from '@/protocol';

export type OutputHandler = (base64Data: string) => void;

export class SessionStore extends Observable {
  private sessionList: SessionInfo[] = [];
  private active: string | null = null;
  private readonly cwds = new Map<string, string>();
  private readonly outputHandlers = new Map<string, OutputHandler>();

  get sessions(): SessionInfo[] {
    return this.sessionList;
  }

  get activeSessionId(): string | null {
    return this.active;
  }

  setActiveSessionId(id: string | null): void {
    if (this.active === id) return;
    this.active = id;
    this.notify();
  }

  session(id: string): SessionInfo | undefined {
    return this.sessionList.find((s) => s.id === id);
  }

  cwd(sessionId: string): string | undefined {
    return this.cwds.get(sessionId);
  }

  updateCwd(sessionId: string, cwd: string): void {
    const trimmed = cwd.trim();
    if (trimmed.length === 0) return;
    if (this.cwds.get(sessionId) !== trimmed) {
      this.cwds.set(sessionId, trimmed);
      this.notify();
    }
  }

  registerOutputHandler(sessionId: string, handler: OutputHandler): void {
    this.outputHandlers.set(sessionId, handler);
  }

  unregisterOutputHandler(sessionId: string): void {
    this.outputHandlers.delete(sessionId);
  }

  handle(message: ServerMessage): void {
    switch (message.type) {
      case 'session_list':
        this.sessionList = message.sessions;
        this.notify();
        break;
      case 'session_created':
        if (!this.sessionList.some((s) => s.id === message.session.id)) {
          this.sessionList = [...this.sessionList, message.session];
          this.notify();
        }
        break;
      case 'agent_session_created':
        if (!this.sessionList.some((s) => s.id === message.session.id)) {
          this.sessionList = [...this.sessionList, message.session];
          this.notify();
        }
        break;
      case 'session_closed':
        this.sessionList = this.sessionList.filter(
          (s) => s.id !== message.sessionId,
        );
        if (this.active === message.sessionId) this.active = null;
        this.outputHandlers.delete(message.sessionId);
        this.cwds.delete(message.sessionId);
        this.notify();
        break;
      case 'output':
      case 'scrollback':
        this.outputHandlers.get(message.sessionId)?.(message.data);
        break;
      default:
        // Other message types are owned by their dedicated stores.
        break;
    }
  }
}
