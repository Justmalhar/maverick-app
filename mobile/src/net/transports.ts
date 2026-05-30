/**
 * TransportTier abstraction. ADR-3's long-term goal is "laptop = server,
 * anything = client" reachable over multiple network paths. We define a single
 * `Transport` interface and three tiers:
 *
 *   - LAN (ws://) — implemented now; raw WebSocket on the local network.
 *   - iroh P2P    — stubbed; QUIC hole-punched direct connection (later).
 *   - relay       — stubbed; fallback through a rendezvous/relay server.
 *
 * The ConnectionManager only ever speaks to a `Transport`, so adding a tier is
 * a matter of providing a new factory — no manager changes required (mirrors
 * the desktop's "new renderer = zero changes outside providers" rule).
 */

export type TransportTier = 'lan' | 'iroh' | 'relay';

export type TransportState = 'closed' | 'opening' | 'open';

export interface TransportHandlers {
  onOpen: () => void;
  onMessage: (text: string) => void;
  /** code/reason are best-effort; clean close vs error both route here. */
  onClose: (info: { code?: number; reason?: string; error?: boolean }) => void;
}

/**
 * A minimal duplex text channel. Implementations wrap whatever underlying
 * primitive they use (WebSocket, iroh stream, …) behind this contract.
 */
export interface Transport {
  readonly tier: TransportTier;
  readonly state: TransportState;
  open(handlers: TransportHandlers): void;
  send(text: string): void;
  close(): void;
}

/** Anything WebSocket-shaped (the global, or a test double). */
export interface WebSocketLike {
  onopen: ((this: unknown, ev: unknown) => unknown) | null;
  onmessage: ((this: unknown, ev: { data: unknown }) => unknown) | null;
  onclose:
    | ((this: unknown, ev: { code?: number; reason?: string }) => unknown)
    | null;
  onerror: ((this: unknown, ev: unknown) => unknown) | null;
  send(data: string): void;
  close(code?: number, reason?: string): void;
}

export type WebSocketFactory = (url: string) => WebSocketLike;

function defaultWebSocketFactory(url: string): WebSocketLike {
  const Ctor = (globalThis as { WebSocket?: new (url: string) => WebSocketLike })
    .WebSocket;
  if (!Ctor) {
    throw new Error('No global WebSocket available for LAN transport');
  }
  return new Ctor(url);
}

/**
 * LAN WebSocket transport. URL is a full `ws://host:port/ws[?token=...]`.
 * Injectable factory keeps it testable without a real socket.
 */
export class LanTransport implements Transport {
  readonly tier: TransportTier = 'lan';
  state: TransportState = 'closed';

  private socket: WebSocketLike | null = null;

  constructor(
    private readonly url: string,
    private readonly factory: WebSocketFactory = defaultWebSocketFactory,
  ) {}

  open(handlers: TransportHandlers): void {
    if (this.state !== 'closed') return;
    this.state = 'opening';
    const sock = this.factory(this.url);
    this.socket = sock;
    sock.onopen = () => {
      this.state = 'open';
      handlers.onOpen();
    };
    sock.onmessage = (ev) => {
      if (typeof ev.data === 'string') handlers.onMessage(ev.data);
    };
    sock.onclose = (ev) => {
      this.state = 'closed';
      this.socket = null;
      handlers.onClose({ code: ev.code, reason: ev.reason });
    };
    sock.onerror = () => {
      // Some platforms fire onerror without onclose; normalise to a close.
      const wasOpening = this.state !== 'closed';
      this.state = 'closed';
      this.socket = null;
      if (wasOpening) handlers.onClose({ error: true });
    };
  }

  send(text: string): void {
    if (this.state !== 'open' || !this.socket) return;
    this.socket.send(text);
  }

  close(): void {
    const sock = this.socket;
    this.state = 'closed';
    this.socket = null;
    if (sock) {
      sock.onopen = null;
      sock.onmessage = null;
      sock.onclose = null;
      sock.onerror = null;
      sock.close(1000, 'client closed');
    }
  }
}

/**
 * iroh P2P transport — stub. Reserved for the QUIC direct-connect tier. RN-2+
 * wires the native iroh module; calling open() before that throws so callers
 * fail loudly rather than silently hanging.
 */
export class IrohTransport implements Transport {
  readonly tier: TransportTier = 'iroh';
  state: TransportState = 'closed';

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  constructor(private readonly nodeTicket: string) {}

  open(_handlers: TransportHandlers): void {
    // TODO(RN-2 / Companion-5): bind expo-iroh native module.
    throw new Error('IrohTransport not yet implemented (Companion-5)');
  }

  send(_text: string): void {
    throw new Error('IrohTransport not yet implemented (Companion-5)');
  }

  close(): void {
    this.state = 'closed';
  }
}

/**
 * Relay transport — stub. Reserved for the rendezvous/relay fallback tier when
 * neither LAN nor direct P2P is reachable.
 */
export class RelayTransport implements Transport {
  readonly tier: TransportTier = 'relay';
  state: TransportState = 'closed';

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  constructor(private readonly relayUrl: string) {}

  open(_handlers: TransportHandlers): void {
    // TODO(RN-2 / Companion-5): connect through relay server.
    throw new Error('RelayTransport not yet implemented (Companion-5)');
  }

  send(_text: string): void {
    throw new Error('RelayTransport not yet implemented (Companion-5)');
  }

  close(): void {
    this.state = 'closed';
  }
}

/** Build the canonical LAN URL from host/port/token, matching the Swift client. */
export function lanUrl(host: string, port = 8765, token = ''): string {
  return token
    ? `ws://${host}:${port}/ws?token=${encodeURIComponent(token)}`
    : `ws://${host}:${port}/ws`;
}
