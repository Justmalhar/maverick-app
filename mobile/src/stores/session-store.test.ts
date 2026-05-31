import { SessionStore } from './session-store';
import { sessionInfo, uuid } from '@/test/fixtures';
import { encodeBase64 } from '@/protocol/primitives';

describe('SessionStore', () => {
  it('replaces the list on session_list and notifies', () => {
    const s = new SessionStore();
    let fired = 0;
    s.subscribe(() => fired++);
    const a = sessionInfo({ name: 'a' });
    s.handle({ type: 'session_list', sessions: [a] });
    expect(s.sessions).toEqual([a]);
    expect(s.session(a.id)).toEqual(a);
    expect(fired).toBe(1);
  });

  it('appends created and agent-created sessions, deduping', () => {
    const s = new SessionStore();
    const a = sessionInfo();
    s.handle({ type: 'session_created', session: a });
    s.handle({ type: 'session_created', session: a });
    expect(s.sessions).toHaveLength(1);
    const b = sessionInfo({ agentProvider: 'claudeCode' });
    s.handle({ type: 'agent_session_created', session: b });
    s.handle({ type: 'agent_session_created', session: b });
    expect(s.sessions).toHaveLength(2);
  });

  it('tracks the active session', () => {
    const s = new SessionStore();
    s.setActiveSessionId('X');
    expect(s.activeSessionId).toBe('X');
    let fired = 0;
    s.subscribe(() => fired++);
    s.setActiveSessionId('X');
    expect(fired).toBe(0);
    s.setActiveSessionId(null);
    expect(s.activeSessionId).toBeNull();
    expect(fired).toBe(1);
  });

  it('updates cwd, ignoring blanks and no-op writes', () => {
    const s = new SessionStore();
    const id = uuid();
    let fired = 0;
    s.subscribe(() => fired++);
    s.updateCwd(id, '   ');
    expect(s.cwd(id)).toBeUndefined();
    s.updateCwd(id, '  /proj  ');
    expect(s.cwd(id)).toBe('/proj');
    s.updateCwd(id, '/proj');
    expect(fired).toBe(1);
  });

  it('removes a session on close and clears active/cwd/handler', () => {
    const s = new SessionStore();
    const a = sessionInfo();
    s.handle({ type: 'session_created', session: a });
    s.setActiveSessionId(a.id);
    s.updateCwd(a.id, '/proj');
    let got = '';
    s.registerOutputHandler(a.id, (d) => (got = d));
    s.handle({ type: 'session_closed', sessionId: a.id });
    expect(s.sessions).toHaveLength(0);
    expect(s.activeSessionId).toBeNull();
    expect(s.cwd(a.id)).toBeUndefined();
    s.handle({ type: 'output', sessionId: a.id, data: 'x' });
    expect(got).toBe('');
  });

  it('keeps a different active session when another closes', () => {
    const s = new SessionStore();
    const a = sessionInfo();
    const b = sessionInfo();
    s.handle({ type: 'session_created', session: a });
    s.handle({ type: 'session_created', session: b });
    s.setActiveSessionId(a.id);
    s.handle({ type: 'session_closed', sessionId: b.id });
    expect(s.activeSessionId).toBe(a.id);
  });

  it('routes output and scrollback to the registered handler', () => {
    const s = new SessionStore();
    const a = sessionInfo();
    const frames: string[] = [];
    s.registerOutputHandler(a.id, (d) => frames.push(d));
    const b64 = encodeBase64(new TextEncoder().encode('hi'));
    s.handle({ type: 'output', sessionId: a.id, data: b64 });
    s.handle({ type: 'scrollback', sessionId: a.id, data: b64 });
    expect(frames).toEqual([b64, b64]);
    s.unregisterOutputHandler(a.id);
    s.handle({ type: 'output', sessionId: a.id, data: b64 });
    expect(frames).toHaveLength(2);
  });

  it('ignores unrelated message types', () => {
    const s = new SessionStore();
    let fired = 0;
    s.subscribe(() => fired++);
    s.handle({ type: 'error', message: 'boom' });
    expect(fired).toBe(0);
  });
});
