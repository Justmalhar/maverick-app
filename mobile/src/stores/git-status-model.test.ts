import { diffKey, GitStatusModel } from './git-status-model';
import { FakeClient } from '@/test/fixtures';
import { GitStatus } from '@/protocol';

function setup(): { model: GitStatusModel; client: FakeClient } {
  const client = new FakeClient();
  return { model: new GitStatusModel(client.asClient()), client };
}

const STATUS: GitStatus = {
  isRepo: true,
  branch: 'main',
  ahead: 1,
  behind: 0,
  files: [{ path: 'a.ts', status: 'M', staged: false }],
};

describe('diffKey', () => {
  it('namespaces staged vs working-tree', () => {
    expect(diffKey('a', true)).toBe('S:a');
    expect(diffKey('a', false)).toBe('U:a');
  });
});

describe('GitStatusModel', () => {
  it('starts idle and not-a-repo', () => {
    const { model } = setup();
    expect(model.state.kind).toBe('idle');
    expect(model.status.isRepo).toBe(false);
  });

  it('refreshes status and loads the result', () => {
    const { model, client } = setup();
    model.refresh('  /proj  ');
    expect(model.path).toBe('/proj');
    expect(model.state.kind).toBe('loading');
    const reqId = (client.last() as { requestId: string }).requestId;
    model.handle({ type: 'git_status_result', requestId: reqId, status: STATUS });
    expect(model.state.kind).toBe('loaded');
    expect(model.status.branch).toBe('main');
  });

  it('ignores blank refresh paths', () => {
    const { model, client } = setup();
    model.refresh('   ');
    expect(client.sent).toHaveLength(0);
  });

  it('ignores status results for a superseded request', () => {
    const { model } = setup();
    model.refresh('/proj');
    model.handle({ type: 'git_status_result', requestId: 'stale', status: STATUS });
    expect(model.state.kind).toBe('loading');
  });

  it('surfaces a status failure', () => {
    const { model, client } = setup();
    model.refresh('/proj');
    const reqId = (client.last() as { requestId: string }).requestId;
    model.handle({ type: 'git_status_failed', requestId: reqId, message: 'nope' });
    expect(model.state).toEqual({ kind: 'error', message: 'nope' });
    model.handle({ type: 'git_status_failed', requestId: 'stale', message: 'x' });
    expect(model.state).toEqual({ kind: 'error', message: 'nope' });
  });

  it('fetches and caches a diff, deduping in-flight + cached requests', () => {
    const { model, client } = setup();
    model.refresh('/proj');
    client.sent.length = 0;
    model.fetchDiff('a.ts', false);
    expect(model.isDiffPending('a.ts', false)).toBe(true);
    const reqId = (client.last() as { requestId: string }).requestId;
    // Dedup while in flight.
    model.fetchDiff('a.ts', false);
    expect(client.sent).toHaveLength(1);
    model.handle({
      type: 'git_diff_result',
      requestId: reqId,
      file: 'a.ts',
      diff: '@@ x',
      truncated: true,
    });
    expect(model.isDiffPending('a.ts', false)).toBe(false);
    expect(model.diff('a.ts', false)).toEqual({ text: '@@ x', truncated: true });
    // Dedup when cached.
    model.fetchDiff('a.ts', false);
    expect(client.sent).toHaveLength(1);
  });

  it('records a diff failure as a placeholder diff', () => {
    const { model, client } = setup();
    model.refresh('/proj');
    client.sent.length = 0;
    model.fetchDiff('b.ts', true);
    const reqId = (client.last() as { requestId: string }).requestId;
    model.handle({ type: 'git_diff_failed', requestId: reqId, message: 'boom' });
    expect(model.diff('b.ts', true)).toEqual({
      text: '[diff failed] boom',
      truncated: false,
    });
  });

  it('ignores diff replies for unknown request ids', () => {
    const { model } = setup();
    model.handle({
      type: 'git_diff_result',
      requestId: 'unknown',
      file: 'x',
      diff: 'd',
      truncated: false,
    });
    model.handle({ type: 'git_diff_failed', requestId: 'unknown', message: 'm' });
    expect(model.diff('x', false)).toBeUndefined();
  });

  it('ignores unrelated messages', () => {
    const { model } = setup();
    let fired = 0;
    model.subscribe(() => fired++);
    model.handle({ type: 'error', message: 'x' });
    expect(fired).toBe(0);
  });
});
