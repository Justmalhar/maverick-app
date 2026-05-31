import { categorize, SessionPicker } from './session-picker';
import { SessionStore } from './session-store';
import { FakeClient, sessionInfo } from '@/test/fixtures';

function setup(): {
  picker: SessionPicker;
  store: SessionStore;
  client: FakeClient;
} {
  const client = new FakeClient();
  const store = new SessionStore();
  return { picker: new SessionPicker(client.asClient(), store), store, client };
}

describe('categorize', () => {
  it('classifies agent vs terminal sessions', () => {
    expect(categorize(sessionInfo({ agentProvider: 'codex' }))).toBe('agent');
    expect(categorize(sessionInfo())).toBe('terminal');
  });
});

describe('SessionPicker', () => {
  it('requests the session list on refresh', () => {
    const { picker, client } = setup();
    picker.refresh();
    expect(client.last()).toEqual({ type: 'list_sessions' });
  });

  it('returns name-sorted, categorised rows', () => {
    const { picker, store } = setup();
    store.handle({
      type: 'session_list',
      sessions: [
        sessionInfo({ name: 'zsh' }),
        sessionInfo({ name: 'claude', agentProvider: 'claudeCode' }),
        sessionInfo({ name: 'Build' }),
      ],
    });
    expect(picker.rows().map((r) => r.session.name)).toEqual([
      'Build',
      'claude',
      'zsh',
    ]);
    expect(picker.agents().map((r) => r.session.name)).toEqual(['claude']);
    expect(picker.terminals().map((r) => r.session.name)).toEqual([
      'Build',
      'zsh',
    ]);
    expect(picker.agents()[0]!.resumable).toBe(true);
    expect(picker.terminals()[0]!.resumable).toBe(false);
  });

  it('attaches without changing mode', () => {
    const { picker, client, store } = setup();
    picker.attach('S1');
    expect(client.sent).toEqual([{ type: 'attach_session', sessionId: 'S1' }]);
    expect(store.activeSessionId).toBe('S1');
  });

  it('resumes by attaching and flipping to chat mode', () => {
    const { picker, client, store } = setup();
    picker.resume('S2');
    expect(client.sent).toEqual([
      { type: 'attach_session', sessionId: 'S2' },
      { type: 'switch_session_mode', sessionId: 'S2', mode: 'chat' },
    ]);
    expect(store.activeSessionId).toBe('S2');
  });
});
