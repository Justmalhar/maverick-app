import { LanTransport, TransportHandlers, WebSocketLike } from './transports';

class FakeSocket implements WebSocketLike {
  onopen: ((this: unknown, ev: unknown) => unknown) | null = null;
  onmessage: ((this: unknown, ev: { data: unknown }) => unknown) | null = null;
  onclose:
    | ((this: unknown, ev: { code?: number; reason?: string }) => unknown)
    | null = null;
  onerror: ((this: unknown, ev: unknown) => unknown) | null = null;
  sent: string[] = [];
  closeCalls: Array<{ code?: number; reason?: string }> = [];

  send(data: string): void {
    this.sent.push(data);
  }

  close(code?: number, reason?: string): void {
    this.closeCalls.push({ code, reason });
  }
}

function handlers(): TransportHandlers & {
  opens: number;
  messages: string[];
  closes: Array<{ error?: boolean }>;
} {
  const opens = { count: 0 };
  const messages: string[] = [];
  const closes: Array<{ error?: boolean }> = [];
  return {
    opens: 0,
    messages,
    closes,
    onOpen() {
      opens.count++;
      (this as { opens: number }).opens = opens.count;
    },
    onMessage(text: string) {
      messages.push(text);
    },
    onClose(info) {
      closes.push({ error: info.error });
    },
  };
}

describe('LanTransport', () => {
  test('open → onOpen sets state open; messages route through; close is clean', () => {
    const sock = new FakeSocket();
    const t = new LanTransport('ws://h/ws', () => sock);
    const h = handlers();
    t.open(h);
    expect(t.state).toBe('opening');

    sock.onopen?.call(sock, {});
    expect(t.state).toBe('open');
    expect(h.opens).toBe(1);

    sock.onmessage?.call(sock, { data: 'hello' });
    sock.onmessage?.call(sock, { data: 42 }); // non-string ignored
    expect(h.messages).toEqual(['hello']);

    t.send('payload');
    expect(sock.sent).toEqual(['payload']);

    t.close();
    expect(t.state).toBe('closed');
    expect(sock.closeCalls[0]).toEqual({ code: 1000, reason: 'client closed' });
  });

  test('send is a no-op before open', () => {
    const sock = new FakeSocket();
    const t = new LanTransport('ws://h/ws', () => sock);
    t.open(handlers());
    t.send('early');
    expect(sock.sent).toEqual([]);
  });

  test('onclose from the socket reports a clean close', () => {
    const sock = new FakeSocket();
    const t = new LanTransport('ws://h/ws', () => sock);
    const h = handlers();
    t.open(h);
    sock.onopen?.call(sock, {});
    sock.onclose?.call(sock, { code: 1006, reason: 'bye' });
    expect(t.state).toBe('closed');
    expect(h.closes).toEqual([{ error: undefined }]);
  });

  test('onerror is normalised to an error close', () => {
    const sock = new FakeSocket();
    const t = new LanTransport('ws://h/ws', () => sock);
    const h = handlers();
    t.open(h);
    sock.onerror?.call(sock, {});
    expect(t.state).toBe('closed');
    expect(h.closes).toEqual([{ error: true }]);
  });

  test('onerror after onclose does not re-report a close', () => {
    const sock = new FakeSocket();
    const t = new LanTransport('ws://h/ws', () => sock);
    const h = handlers();
    t.open(h);
    sock.onopen?.call(sock, {});
    // onclose flips state→closed but leaves sock.onerror attached.
    sock.onclose?.call(sock, { code: 1006 });
    expect(h.closes).toHaveLength(1);
    // A subsequent onerror sees state==='closed', so wasOpening is false and
    // the error-close branch must NOT fire a second close.
    sock.onerror?.call(sock, {});
    expect(h.closes).toHaveLength(1);
  });

  test('close before open is a no-op (no socket to tear down)', () => {
    const t = new LanTransport('ws://h/ws', () => new FakeSocket());
    expect(() => t.close()).not.toThrow();
    expect(t.state).toBe('closed');
  });

  test('double open is ignored', () => {
    let built = 0;
    const t = new LanTransport('ws://h/ws', () => {
      built++;
      return new FakeSocket();
    });
    t.open(handlers());
    t.open(handlers());
    expect(built).toBe(1);
  });

  test('default factory throws when no global WebSocket', () => {
    const original = (globalThis as { WebSocket?: unknown }).WebSocket;
    delete (globalThis as { WebSocket?: unknown }).WebSocket;
    try {
      const t = new LanTransport('ws://h/ws');
      expect(() => t.open(handlers())).toThrow(/No global WebSocket/);
    } finally {
      if (original !== undefined) {
        (globalThis as { WebSocket?: unknown }).WebSocket = original;
      }
    }
  });

  test('default factory uses the global WebSocket when present', () => {
    const original = (globalThis as { WebSocket?: unknown }).WebSocket;
    const built: string[] = [];
    (globalThis as { WebSocket?: unknown }).WebSocket = class {
      onopen = null;
      onmessage = null;
      onclose = null;
      onerror = null;
      constructor(url: string) {
        built.push(url);
      }
      send() {}
      close() {}
    };
    try {
      const t = new LanTransport('ws://h/ws');
      t.open(handlers());
      expect(built).toEqual(['ws://h/ws']);
    } finally {
      if (original === undefined) {
        delete (globalThis as { WebSocket?: unknown }).WebSocket;
      } else {
        (globalThis as { WebSocket?: unknown }).WebSocket = original;
      }
    }
  });
});
