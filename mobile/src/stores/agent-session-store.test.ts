import { AgentSessionStore } from './agent-session-store';
import { agentEvent, sessionInfo, uuid } from '@/test/fixtures';

describe('AgentSessionStore', () => {
  it('creates a model on agent_session_created (with provider)', () => {
    const store = new AgentSessionStore();
    let fired = 0;
    store.subscribe(() => fired++);
    const info = sessionInfo({ agentProvider: 'codex', sessionMode: 'chat' });
    store.handle({ type: 'agent_session_created', session: info });
    expect(store.session(info.id)?.provider).toBe('codex');
    expect(fired).toBe(1);
    // Idempotent.
    store.handle({ type: 'agent_session_created', session: info });
    expect(fired).toBe(1);
  });

  it('defaults sessionMode to chat when missing', () => {
    const store = new AgentSessionStore();
    const info = sessionInfo({ agentProvider: 'claudeCode' });
    store.handle({ type: 'agent_session_created', session: info });
    expect(store.session(info.id)?.mode).toBe('chat');
  });

  it('ignores agent_session_created without a provider', () => {
    const store = new AgentSessionStore();
    const info = sessionInfo();
    store.handle({ type: 'agent_session_created', session: info });
    expect(store.session(info.id)).toBeUndefined();
  });

  it('lazily creates a model from a session_start agent_event', () => {
    const store = new AgentSessionStore();
    const id = uuid();
    store.handle(
      agentEvent(id, {
        type: 'session_start',
        id: 'a',
        provider: 'opencode',
        cwd: '/p',
        source: 'resume',
      }),
    );
    expect(store.session(id)?.provider).toBe('opencode');
  });

  it('lazily creates a claudeCode stub for a non-start first event', () => {
    const store = new AgentSessionStore();
    const id = uuid();
    store.handle(agentEvent(id, { type: 'user_message', text: 'hi' }));
    const m = store.session(id);
    expect(m?.provider).toBe('claudeCode');
    expect(m?.items[0]).toMatchObject({ kind: 'user', text: 'hi' });
  });

  it('routes events to an existing model', () => {
    const store = new AgentSessionStore();
    const info = sessionInfo({ agentProvider: 'claudeCode' });
    store.handle({ type: 'agent_session_created', session: info });
    store.handle(agentEvent(info.id, { type: 'user_message', text: 'yo' }));
    expect(store.session(info.id)?.items).toHaveLength(1);
  });

  it('removes the model on session_closed', () => {
    const store = new AgentSessionStore();
    const info = sessionInfo({ agentProvider: 'claudeCode' });
    store.handle({ type: 'agent_session_created', session: info });
    let fired = 0;
    store.subscribe(() => fired++);
    store.handle({ type: 'session_closed', sessionId: info.id });
    expect(store.session(info.id)).toBeUndefined();
    expect(fired).toBe(1);
    store.handle({ type: 'session_closed', sessionId: info.id });
    expect(fired).toBe(1);
  });

  it('ignores unrelated messages', () => {
    const store = new AgentSessionStore();
    store.handle({ type: 'error', message: 'x' });
    expect(store.session('any')).toBeUndefined();
  });
});
