import { defaultManager, MaverickClient } from './maverick-client';
import { ConnectionManager } from '@/net/connection-manager';
import { Transport, TransportHandlers } from '@/net/transports';
import {
  decodeClientMessageFromString,
  ClientMessage,
} from '@/protocol';

class FakeTransport implements Transport {
  readonly tier = 'lan' as const;
  state: 'closed' | 'opening' | 'open' = 'closed';
  sent: string[] = [];
  private handlers: TransportHandlers | null = null;

  open(handlers: TransportHandlers): void {
    this.handlers = handlers;
    this.state = 'open';
    handlers.onOpen();
  }
  send(text: string): void {
    this.sent.push(text);
  }
  close(): void {
    this.state = 'closed';
  }
  emit(text: string): void {
    this.handlers?.onMessage(text);
  }
}

function setup(): { client: MaverickClient; transport: FakeTransport } {
  let transport!: FakeTransport;
  const manager = new ConnectionManager({
    transportFactory: () => {
      transport = new FakeTransport();
      return transport;
    },
  });
  const client = new MaverickClient(manager);
  client.connect({ host: 'mac.local', port: 8765, token: 'tok' });
  return { client, transport };
}

function lastMessage(t: FakeTransport): ClientMessage {
  return decodeClientMessageFromString(t.sent[t.sent.length - 1]!);
}

describe('defaultManager', () => {
  it('builds a LAN ConnectionManager that dials a real WebSocket', () => {
    class StubWS {
      onopen: (() => void) | null = null;
      onmessage: unknown = null;
      onclose: unknown = null;
      onerror: unknown = null;
      send(): void {}
      close(): void {}
    }
    const prior = (globalThis as { WebSocket?: unknown }).WebSocket;
    (globalThis as { WebSocket?: unknown }).WebSocket = StubWS as unknown;
    try {
      const manager = defaultManager();
      manager.connect('ws://mac.local:8765/ws');
      expect(manager.state).toBe('connecting');
      manager.disconnect();
    } finally {
      (globalThis as { WebSocket?: unknown }).WebSocket = prior;
    }
  });
});

describe('MaverickClient', () => {
  it('builds a default ConnectionManager when none is injected', () => {
    const c = new MaverickClient();
    expect(c.state).toBe('disconnected');
    expect(c.lastError).toBeNull();
    expect(c.target).toBeNull();
  });

  it('connects, exposes state/target, and disconnects', () => {
    const { client } = setup();
    expect(client.state).toBe('connected');
    expect(client.target).toEqual({
      host: 'mac.local',
      port: 8765,
      token: 'tok',
    });
    client.disconnect();
    expect(client.state).toBe('disconnected');
  });

  it('generates UPPERCASE UUID request ids', () => {
    const { client } = setup();
    expect(client.requestId()).toMatch(
      /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/,
    );
  });

  it('sends every typed message variant', () => {
    const { client, transport } = setup();
    const sid = '11111111-1111-4111-8111-111111111111';
    const rid = '22222222-2222-4222-8222-222222222222';

    client.listSessions();
    expect(lastMessage(transport).type).toBe('list_sessions');

    client.attach(sid);
    expect(lastMessage(transport)).toMatchObject({ type: 'attach_session' });

    client.createSession('build', '/bin/zsh', '/proj');
    expect(lastMessage(transport)).toMatchObject({
      type: 'create_session',
      name: 'build',
      shell: '/bin/zsh',
      cwd: '/proj',
    });
    client.createSession('build', '/bin/zsh');
    expect(lastMessage(transport)).not.toHaveProperty('cwd');

    client.createAgentSession('claude', 'claudeCode', '/proj');
    expect(lastMessage(transport)).toMatchObject({
      type: 'create_agent_session',
      provider: 'claudeCode',
      cwd: '/proj',
    });
    client.createAgentSession('claude', 'claudeCode');
    expect(lastMessage(transport)).not.toHaveProperty('cwd');

    client.closeSession(sid);
    expect(lastMessage(transport).type).toBe('close_session');

    client.switchSessionMode(sid, 'terminal');
    expect(lastMessage(transport)).toMatchObject({
      type: 'switch_session_mode',
      mode: 'terminal',
    });

    client.input(sid, 'ls\r');
    expect(lastMessage(transport)).toMatchObject({ type: 'input', data: 'ls\r' });

    client.resize(sid, 80, 24);
    expect(lastMessage(transport)).toMatchObject({
      type: 'resize',
      cols: 80,
      rows: 24,
    });

    client.agentInput(sid, 'hi');
    expect(lastMessage(transport)).toMatchObject({
      type: 'agent_input',
      text: 'hi',
    });

    client.respondToPermission(sid, rid, true);
    expect(lastMessage(transport)).toMatchObject({
      type: 'permission_response',
      allowed: true,
    });

    client.listDirectory(rid, '/proj');
    expect(lastMessage(transport)).toMatchObject({
      type: 'list_directory',
      path: '/proj',
    });
    client.listDirectory(rid);
    expect(lastMessage(transport)).not.toHaveProperty('path');

    client.indexProject(rid, '/proj', true);
    expect(lastMessage(transport)).toMatchObject({
      type: 'index_project',
      refresh: true,
    });

    client.gitStatus(rid, '/proj');
    expect(lastMessage(transport).type).toBe('git_status');

    client.gitDiff(rid, '/proj', 'a.ts', true);
    expect(lastMessage(transport)).toMatchObject({
      type: 'git_diff',
      file: 'a.ts',
      staged: true,
    });
  });
});
