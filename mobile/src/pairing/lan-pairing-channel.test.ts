import {
  LanPairingChannel,
  lanPairingUrl,
} from './lan-pairing-channel';
import { bytesToBase64url } from './base64url';

interface SocketLike {
  onopen: (() => void) | null;
  onmessage: ((ev: { data: unknown }) => void) | null;
  onerror: ((ev: unknown) => void) | null;
  send(data: string): void;
  close(): void;
}

class FakeSocket implements SocketLike {
  static last: FakeSocket | null = null;
  onopen: (() => void) | null = null;
  onmessage: ((ev: { data: unknown }) => void) | null = null;
  onerror: ((ev: unknown) => void) | null = null;
  readonly sent: string[] = [];
  closed = false;

  constructor(readonly url: string) {
    FakeSocket.last = this;
  }

  send(data: string): void {
    this.sent.push(data);
  }
  close(): void {
    this.closed = true;
  }
  open(): void {
    this.onopen?.();
  }
  message(data: unknown): void {
    this.onmessage?.({ data });
  }
  error(): void {
    this.onerror?.(new Error('boom'));
  }
}

const original = (globalThis as { WebSocket?: unknown }).WebSocket;

function installFakeWebSocket(): void {
  (globalThis as { WebSocket?: unknown }).WebSocket =
    FakeSocket as unknown as new (u: string) => SocketLike;
}

afterEach(() => {
  (globalThis as { WebSocket?: unknown }).WebSocket = original;
  FakeSocket.last = null;
});

describe('lanPairingUrl', () => {
  it('builds the ws pairing URL', () => {
    expect(lanPairingUrl('mac.local', 8765)).toBe('ws://mac.local:8765/pair');
  });
});

describe('LanPairingChannel', () => {
  it('throws when no global WebSocket is available', () => {
    delete (globalThis as { WebSocket?: unknown }).WebSocket;
    expect(() => new LanPairingChannel('ws://x/pair')).toThrow(
      /No global WebSocket/,
    );
  });

  it('queues sends before open and flushes them in order on open', () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://mac.local:8765/pair');
    const sock = FakeSocket.last!;

    // Send before the socket opens — must NOT write to the CONNECTING socket.
    channel.send(new Uint8Array([1, 2, 3]));
    channel.send(new Uint8Array([4, 5]));
    expect(sock.sent).toHaveLength(0);

    sock.open();
    expect(sock.sent).toEqual([
      bytesToBase64url(new Uint8Array([1, 2, 3])),
      bytesToBase64url(new Uint8Array([4, 5])),
    ]);

    // After open, sends go straight through.
    channel.send(new Uint8Array([6]));
    expect(sock.sent[2]).toBe(bytesToBase64url(new Uint8Array([6])));
  });

  it('ready() resolves once the socket opens', async () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://x/pair');
    const sock = FakeSocket.last!;
    const ready = channel.ready();
    sock.open();
    await expect(ready).resolves.toBeUndefined();
  });

  it('ready() rejects on socket error', async () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://x/pair');
    const sock = FakeSocket.last!;
    const ready = channel.ready();
    sock.error();
    await expect(ready).rejects.toThrow(/Pairing socket error/);
  });

  it('delivers a buffered inbound frame to a later receive()', async () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://x/pair');
    const sock = FakeSocket.last!;
    sock.message(bytesToBase64url(new Uint8Array([9, 8, 7])));
    const frame = await channel.receive();
    expect(Array.from(frame)).toEqual([9, 8, 7]);
  });

  it('resolves a pending receive() when a frame arrives', async () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://x/pair');
    const sock = FakeSocket.last!;
    const pending = channel.receive();
    sock.message(bytesToBase64url(new Uint8Array([1])));
    const frame = await pending;
    expect(Array.from(frame)).toEqual([1]);
  });

  it('ignores non-string inbound messages', async () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://x/pair');
    const sock = FakeSocket.last!;
    sock.message(new ArrayBuffer(4)); // non-string → dropped
    sock.message(bytesToBase64url(new Uint8Array([2])));
    const frame = await channel.receive();
    expect(Array.from(frame)).toEqual([2]);
  });

  it('close() closes the underlying socket', () => {
    installFakeWebSocket();
    const channel = new LanPairingChannel('ws://x/pair');
    const sock = FakeSocket.last!;
    channel.close();
    expect(sock.closed).toBe(true);
  });
});
