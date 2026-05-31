/**
 * ConnectionManager — TS port of the desktop Swift ConnectionManager, generalised
 * over a `Transport` (TransportTier) instead of a hard-coded URLSession socket.
 *
 * Behaviour preserved from Swift:
 *   - state machine: disconnected → connecting → connected
 *   - exponential backoff: 1s, doubling, capped at 30s; reset on connect
 *   - monotonic generation id ignores callbacks from superseded transports
 *   - ServerMessage decode failures are dropped (do not crash the socket)
 *
 * Added for the multi-client model: a ServerMessage event emitter and
 * attach/detach session bookkeeping so callers know which sessions this client
 * believes it is subscribed to (used to re-attach after a reconnect).
 */

import {
  ClientMessage,
  decodeServerMessageFromString,
  encodeClientMessageToString,
  ServerMessage,
} from '@/protocol';
import { Emitter } from './emitter';
import { Transport, TransportTier } from './transports';

export type ConnectionState = 'disconnected' | 'connecting' | 'connected';

export interface BackoffConfig {
  initialMs: number;
  maxMs: number;
  factor: number;
}

export const DEFAULT_BACKOFF: BackoffConfig = {
  initialMs: 1000,
  maxMs: 30000,
  factor: 2,
};

export type Scheduler = (fn: () => void, delayMs: number) => unknown;
export type Canceller = (handle: unknown) => void;

export interface ConnectionManagerOptions {
  /** Builds a fresh Transport for each (re)connect attempt. */
  transportFactory: (url: string) => Transport;
  backoff?: BackoffConfig;
  /** Injectable timers — defaults to setTimeout/clearTimeout. */
  setTimer?: Scheduler;
  clearTimer?: Canceller;
  /** When true, automatically re-attach known sessions after reconnect. */
  reattachOnReconnect?: boolean;
}

export class ConnectionManager {
  state: ConnectionState = 'disconnected';
  lastError: string | null = null;

  readonly messages = new Emitter<ServerMessage>();
  readonly states = new Emitter<ConnectionState>();

  private readonly transportFactory: (url: string) => Transport;
  private readonly backoff: BackoffConfig;
  private readonly setTimer: Scheduler;
  private readonly clearTimer: Canceller;
  private readonly reattachOnReconnect: boolean;

  private transport: Transport | null = null;
  private url = '';
  private delayMs: number;
  private generation = 0;
  private reconnectHandle: unknown = null;
  /** Sessions this client is attached to; replayed after reconnect. */
  private readonly attached = new Set<string>();
  private manualClose = false;

  constructor(opts: ConnectionManagerOptions) {
    this.transportFactory = opts.transportFactory;
    this.backoff = opts.backoff ?? DEFAULT_BACKOFF;
    this.setTimer =
      opts.setTimer ?? ((fn, d) => setTimeout(fn, d) as unknown);
    this.clearTimer =
      opts.clearTimer ?? ((h) => clearTimeout(h as ReturnType<typeof setTimeout>));
    this.reattachOnReconnect = opts.reattachOnReconnect ?? true;
    this.delayMs = this.backoff.initialMs;
  }

  // --- public API ----------------------------------------------------------

  connect(url: string): void {
    this.url = url;
    this.manualClose = false;
    this.openTransport();
  }

  disconnect(): void {
    this.manualClose = true;
    this.cancelReconnect();
    this.tearDownTransport();
    this.setState('disconnected');
  }

  send(message: ClientMessage): void {
    if (this.state !== 'connected' || !this.transport) return;
    this.transport.send(encodeClientMessageToString(message));
  }

  /** Track + send an attach. Survives reconnect when reattach is enabled. */
  attach(sessionId: string): void {
    this.attached.add(sessionId);
    this.send({ type: 'attach_session', sessionId });
  }

  /** Stop tracking a session (no detach message exists in the protocol). */
  detach(sessionId: string): void {
    this.attached.delete(sessionId);
  }

  attachedSessions(): string[] {
    return [...this.attached];
  }

  get tier(): TransportTier | null {
    return this.transport?.tier ?? null;
  }

  // --- backoff helpers (exposed for tests, mirrors Swift) -------------------

  nextDelay(): number {
    return this.delayMs;
  }

  recordFailure(): void {
    this.delayMs = Math.min(this.delayMs * this.backoff.factor, this.backoff.maxMs);
  }

  resetDelay(): void {
    this.delayMs = this.backoff.initialMs;
  }

  // --- internals ------------------------------------------------------------

  private setState(next: ConnectionState): void {
    if (this.state === next) return;
    this.state = next;
    this.states.emit(next);
  }

  private openTransport(): void {
    this.tearDownTransport();
    this.setState('connecting');

    this.generation += 1;
    const myGen = this.generation;
    const transport = this.transportFactory(this.url);
    this.transport = transport;

    transport.open({
      onOpen: () => {
        if (myGen !== this.generation) return;
        this.setState('connected');
        this.resetDelay();
        if (this.reattachOnReconnect) {
          for (const sessionId of this.attached) {
            transport.send(
              encodeClientMessageToString({ type: 'attach_session', sessionId }),
            );
          }
        }
      },
      onMessage: (text) => {
        if (myGen !== this.generation) return;
        // Receiving implies open even if onOpen never fired (Swift safety net).
        if (this.state !== 'connected') {
          this.setState('connected');
          this.resetDelay();
        }
        try {
          this.messages.emit(decodeServerMessageFromString(text));
        } catch {
          // Drop undecodable frames rather than tearing down the connection.
        }
      },
      onClose: (info) => {
        if (myGen !== this.generation) return;
        if (info.error) this.lastError = 'transport error';
        this.scheduleReconnect();
      },
    });
  }

  private scheduleReconnect(): void {
    if (this.manualClose) {
      this.setState('disconnected');
      return;
    }
    const delay = this.delayMs;
    this.recordFailure();
    this.setState('disconnected');
    this.cancelReconnect();
    this.reconnectHandle = this.setTimer(() => {
      this.reconnectHandle = null;
      /* istanbul ignore else -- a manual disconnect cancels this timer before
         it can fire, so manualClose is always false here; the guard only
         defends against a scheduler that runs an already-cancelled task. */
      if (!this.manualClose) this.openTransport();
    }, delay);
  }

  private cancelReconnect(): void {
    if (this.reconnectHandle !== null) {
      this.clearTimer(this.reconnectHandle);
      this.reconnectHandle = null;
    }
  }

  private tearDownTransport(): void {
    if (this.transport) {
      this.transport.close();
      this.transport = null;
    }
  }
}
