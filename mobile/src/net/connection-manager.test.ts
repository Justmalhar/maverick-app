import { ClientMessage, ServerMessage } from '@/protocol';
import {
  ConnectionManager,
  ConnectionState,
} from './connection-manager';
import { Emitter } from './emitter';
import {
  IrohTransport,
  lanUrl,
  RelayTransport,
  Transport,
  TransportHandlers,
  TransportTier,
} from './transports';

/** A controllable in-memory transport for state-machine tests. */
class FakeTransport implements Transport {
  readonly tier: TransportTier = 'lan';
  state: 'closed' | 'opening' | 'open' = 'closed';
  handlers: TransportHandlers | null = null;
  sent: string[] = [];
  closed = false;

  constructor(public readonly url: string, private readonly registry: FakeTransport[]) {
    registry.push(this);
  }

  open(handlers: TransportHandlers): void {
    this.state = 'opening';
    this.handlers = handlers;
  }

  send(text: string): void {
    this.sent.push(text);
  }

  close(): void {
    this.closed = true;
    this.state = 'closed';
  }

  // --- test driver helpers ---
  fireOpen(): void {
    this.state = 'open';
    this.handlers?.onOpen();
  }

  fireMessage(text: string): void {
    this.handlers?.onMessage(text);
  }

  fireClose(error = false): void {
    this.state = 'closed';
    this.handlers?.onClose(error ? { error: true } : { code: 1000 });
  }
}

/** A manual scheduler so reconnect timing is deterministic. */
class FakeClock {
  private id = 0;
  private tasks = new Map<number, { fn: () => void; delay: number }>();

  setTimer = (fn: () => void, delay: number): unknown => {
    const handle = ++this.id;
    this.tasks.set(handle, { fn, delay });
    return handle;
  };

  clearTimer = (handle: unknown): void => {
    this.tasks.delete(handle as number);
  };

  /** Run all pending timers (FIFO). */
  flush(): void {
    const pending = [...this.tasks.entries()];
    this.tasks.clear();
    for (const [, task] of pending) task.fn();
  }

  get pendingDelays(): number[] {
    return [...this.tasks.values()].map((t) => t.delay);
  }
}

function makeManager(reattach = true) {
  const registry: FakeTransport[] = [];
  const clock = new FakeClock();
  const manager = new ConnectionManager({
    transportFactory: (url) => new FakeTransport(url, registry),
    setTimer: clock.setTimer,
    clearTimer: clock.clearTimer,
    reattachOnReconnect: reattach,
  });
  return { manager, registry, clock };
}

const SESSION = '11111111-1111-4111-8111-111111111111';

describe('Emitter', () => {
  test('on/off/emit and unsubscribe', () => {
    const e = new Emitter<number>();
    const seen: number[] = [];
    const unsub = e.on((v) => seen.push(v));
    e.emit(1);
    expect(e.size).toBe(1);
    unsub();
    e.emit(2);
    expect(seen).toEqual([1]);
  });

  test('clear removes all listeners', () => {
    const e = new Emitter<number>();
    e.on(() => undefined);
    e.clear();
    expect(e.size).toBe(0);
  });

  test('a listener unsubscribing mid-emit does not skip others', () => {
    const e = new Emitter<number>();
    const seen: string[] = [];
    let unsubB: () => void = () => undefined;
    const a = () => {
      seen.push('a');
      unsubB();
    };
    const b = () => seen.push('b');
    e.on(a);
    unsubB = e.on(b);
    e.emit(0);
    expect(seen).toContain('b');
  });
});

describe('ConnectionManager state machine', () => {
  test('connect → open transitions disconnected → connecting → connected', () => {
    const { manager, registry } = makeManager();
    const states: ConnectionState[] = [];
    manager.states.on((s) => states.push(s));

    expect(manager.state).toBe('disconnected');
    manager.connect(lanUrl('192.168.1.10'));
    expect(manager.state).toBe('connecting');
    registry[0]!.fireOpen();
    expect(manager.state).toBe('connected');
    expect(states).toEqual(['connecting', 'connected']);
    expect(registry[0]!.url).toBe('ws://192.168.1.10:8765/ws');
  });

  test('attach is tracked and sent; messages are decoded + emitted', () => {
    const { manager, registry } = makeManager();
    const received: ServerMessage[] = [];
    manager.messages.on((m) => received.push(m));

    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    manager.attach(SESSION);
    expect(manager.attachedSessions()).toEqual([SESSION]);

    const attachWire = JSON.parse(registry[0]!.sent[0]!) as ClientMessage;
    expect(attachWire).toEqual({ type: 'attach_session', sessionId: SESSION });

    registry[0]!.fireMessage(JSON.stringify({ type: 'output', sessionId: SESSION, data: 'aGk=' }));
    expect(received).toEqual([{ type: 'output', sessionId: SESSION, data: 'aGk=' }]);
  });

  test('send is a no-op until connected', () => {
    const { manager, registry } = makeManager();
    manager.connect(lanUrl('host'));
    manager.send({ type: 'list_sessions' });
    expect(registry[0]!.sent).toEqual([]);
    registry[0]!.fireOpen();
    manager.send({ type: 'list_sessions' });
    expect(registry[0]!.sent).toEqual([JSON.stringify({ type: 'list_sessions' })]);
  });

  test('receiving a message before onOpen flips state to connected (safety net)', () => {
    const { manager, registry } = makeManager();
    manager.connect(lanUrl('host'));
    expect(manager.state).toBe('connecting');
    registry[0]!.fireMessage(JSON.stringify({ type: 'error', message: 'x' }));
    expect(manager.state).toBe('connected');
  });

  test('undecodable frames are dropped without tearing down', () => {
    const { manager, registry } = makeManager();
    const received: ServerMessage[] = [];
    manager.messages.on((m) => received.push(m));
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    registry[0]!.fireMessage('{not json');
    registry[0]!.fireMessage(JSON.stringify({ type: 'totally_unknown' }));
    expect(received).toEqual([]);
    expect(manager.state).toBe('connected');
  });

  test('close → reconnect with exponential backoff, reset on reconnect', () => {
    const { manager, registry, clock } = makeManager();
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    expect(manager.nextDelay()).toBe(1000);

    // First drop schedules a 1s reconnect, then backoff doubles to 2s.
    registry[0]!.fireClose();
    expect(manager.state).toBe('disconnected');
    expect(clock.pendingDelays).toEqual([1000]);
    expect(manager.nextDelay()).toBe(2000);

    clock.flush();
    expect(registry).toHaveLength(2);
    expect(manager.state).toBe('connecting');

    // Reconnecting successfully resets the backoff to 1s.
    registry[1]!.fireOpen();
    expect(manager.nextDelay()).toBe(1000);
  });

  test('backoff caps at 30s', () => {
    const { manager, registry, clock } = makeManager();
    manager.connect(lanUrl('host'));
    for (let i = 0; i < 8; i++) {
      const t = registry[registry.length - 1]!;
      t.fireClose();
      clock.flush();
    }
    expect(manager.nextDelay()).toBe(30000);
  });

  test('attached sessions are re-attached after reconnect', () => {
    const { manager, registry, clock } = makeManager(true);
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    manager.attach(SESSION);

    registry[0]!.fireClose();
    clock.flush();
    registry[1]!.fireOpen();

    const reattach = JSON.parse(registry[1]!.sent[0]!) as ClientMessage;
    expect(reattach).toEqual({ type: 'attach_session', sessionId: SESSION });
  });

  test('reattach disabled means no replay after reconnect', () => {
    const { manager, registry, clock } = makeManager(false);
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    manager.attach(SESSION);
    registry[0]!.fireClose();
    clock.flush();
    registry[1]!.fireOpen();
    expect(registry[1]!.sent).toEqual([]);
  });

  test('detach stops tracking', () => {
    const { manager, registry } = makeManager();
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    manager.attach(SESSION);
    manager.detach(SESSION);
    expect(manager.attachedSessions()).toEqual([]);
  });

  test('disconnect cancels reconnect and closes the transport', () => {
    const { manager, registry, clock } = makeManager();
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    registry[0]!.fireClose();
    expect(clock.pendingDelays).toEqual([1000]);
    manager.disconnect();
    expect(manager.state).toBe('disconnected');
    clock.flush();
    // No new transport created after a manual disconnect.
    expect(registry).toHaveLength(1);
  });

  test('callbacks from a superseded generation are ignored', () => {
    const { manager, registry, clock } = makeManager();
    const received: ServerMessage[] = [];
    manager.messages.on((m) => received.push(m));
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    registry[0]!.fireClose();
    clock.flush();
    registry[1]!.fireOpen();
    // Now registry[1] is current. Late open/message/close from the dead
    // transport[0] are all ignored (generation guard).
    const states: ConnectionState[] = [];
    manager.states.on((s) => states.push(s));
    registry[0]!.fireOpen();
    registry[0]!.fireMessage(JSON.stringify({ type: 'error', message: 'stale' }));
    registry[0]!.fireClose();
    expect(states).toEqual([]);
    expect(received).toEqual([]);
    expect(manager.state).toBe('connected');
  });

  test('error close records lastError', () => {
    const { manager, registry } = makeManager();
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    registry[0]!.fireClose(true);
    expect(manager.lastError).toBe('transport error');
  });

  test('tier reflects the active transport', () => {
    const { manager, registry } = makeManager();
    expect(manager.tier).toBeNull();
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    expect(manager.tier).toBe('lan');
  });

  test('a late close after manual disconnect does not reconnect', () => {
    const { manager, registry, clock } = makeManager();
    manager.connect(lanUrl('host'));
    registry[0]!.fireOpen();
    manager.disconnect();
    // disconnect() does not bump the generation, so a straggler onClose from
    // the same transport passes the gen check and hits the manualClose guard.
    registry[0]!.fireClose();
    expect(manager.state).toBe('disconnected');
    clock.flush();
    expect(registry).toHaveLength(1);
  });

  test('default setTimer/clearTimer fall back to setTimeout/clearTimeout', () => {
    jest.useFakeTimers();
    try {
      const registry: FakeTransport[] = [];
      const manager = new ConnectionManager({
        transportFactory: (url) => new FakeTransport(url, registry),
      });
      manager.connect(lanUrl('host'));
      registry[0]!.fireOpen();
      // Scheduling uses the default setTimeout-backed scheduler.
      registry[0]!.fireClose();
      expect(jest.getTimerCount()).toBe(1);
      // disconnect uses the default clearTimeout-backed canceller.
      manager.disconnect();
      expect(jest.getTimerCount()).toBe(0);
      jest.runOnlyPendingTimers();
      expect(registry).toHaveLength(1);
    } finally {
      jest.useRealTimers();
    }
  });
});

describe('transport helpers + stubs', () => {
  test('lanUrl with and without token', () => {
    expect(lanUrl('h')).toBe('ws://h:8765/ws');
    expect(lanUrl('h', 9000, 'tok en')).toBe('ws://h:9000/ws?token=tok%20en');
  });

  test('iroh + relay transports throw until implemented', () => {
    const iroh = new IrohTransport('ticket');
    expect(iroh.tier).toBe('iroh');
    expect(() => iroh.open({ onOpen() {}, onMessage() {}, onClose() {} })).toThrow();
    expect(() => iroh.send('x')).toThrow();
    iroh.close();
    expect(iroh.state).toBe('closed');

    const relay = new RelayTransport('wss://relay');
    expect(relay.tier).toBe('relay');
    expect(() => relay.open({ onOpen() {}, onMessage() {}, onClose() {} })).toThrow();
    expect(() => relay.send('x')).toThrow();
    relay.close();
    expect(relay.state).toBe('closed');
  });
});
