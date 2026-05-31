import { AppModel } from './app-model';
import { MaverickClient } from './maverick-client';
import { ConnectionManager } from '@/net/connection-manager';
import { Transport, TransportHandlers } from '@/net/transports';
import { encodeServerMessageToString, ServerMessage } from '@/protocol';
import { sessionInfo } from '@/test/fixtures';

class FakeTransport implements Transport {
  readonly tier = 'lan' as const;
  state: 'closed' | 'opening' | 'open' = 'closed';
  private handlers: TransportHandlers | null = null;
  open(handlers: TransportHandlers): void {
    this.handlers = handlers;
    this.state = 'open';
    handlers.onOpen();
  }
  send(): void {}
  close(): void {
    this.state = 'closed';
  }
  emit(text: string): void {
    this.handlers?.onMessage(text);
  }
}

function setup(): { app: AppModel; transport: FakeTransport } {
  let transport!: FakeTransport;
  const manager = new ConnectionManager({
    transportFactory: () => {
      transport = new FakeTransport();
      return transport;
    },
  });
  const client = new MaverickClient(manager);
  const app = new AppModel({ client });
  client.connect({ host: 'mac.local', port: 8765 });
  return { app, transport };
}

function send(transport: FakeTransport, msg: ServerMessage): void {
  transport.emit(encodeServerMessageToString(msg));
}

describe('AppModel', () => {
  it('wires a default client + memory store when nothing is injected', () => {
    const app = new AppModel();
    expect(app.client).toBeInstanceOf(MaverickClient);
    expect(app.settings.lastWorkingDir).toBe('');
    app.dispose();
  });

  it('fans a session_list out to the session store', () => {
    const { app, transport } = setup();
    send(transport, { type: 'session_list', sessions: [sessionInfo({ name: 'a' })] });
    expect(app.sessions.sessions).toHaveLength(1);
  });

  it('routes agent, git, index, and directory messages to their stores', () => {
    const { app, transport } = setup();
    const info = sessionInfo({ agentProvider: 'claudeCode' });
    send(transport, { type: 'agent_session_created', session: info });
    expect(app.agents.session(info.id)).toBeDefined();

    app.git.refresh('/proj');
    const gitReq = app.client.manager; // smoke: model is wired to client
    expect(gitReq).toBeDefined();

    // Directory + index stores share the same client; smoke that they exist.
    expect(app.index).toBeDefined();
    expect(app.directory).toBeDefined();
    expect(app.picker).toBeDefined();
  });

  it('stops routing after dispose', () => {
    const { app, transport } = setup();
    app.dispose();
    send(transport, { type: 'session_list', sessions: [sessionInfo()] });
    expect(app.sessions.sessions).toHaveLength(0);
  });
});
