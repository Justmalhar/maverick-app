import { ProjectIndexModel } from './project-index-model';
import { FakeClient } from '@/test/fixtures';
import { IndexEntry } from '@/protocol';

function setup(): { model: ProjectIndexModel; client: FakeClient } {
  const client = new FakeClient();
  return { model: new ProjectIndexModel(client.asClient()), client };
}

function entry(path: string, isDirectory = false): IndexEntry {
  return { path, isDirectory };
}

function lastReq(client: FakeClient): string {
  return (client.last() as { requestId: string }).requestId;
}

describe('ProjectIndexModel', () => {
  it('indexes a path and dedupes streamed chunks', () => {
    const { model, client } = setup();
    model.index('  /proj  ');
    expect(model.state.kind).toBe('loading');
    const req = lastReq(client);
    model.handle({
      type: 'index_chunk',
      requestId: req,
      root: '/proj',
      entries: [entry('src'), entry('src/a.ts')],
      complete: false,
    });
    model.handle({
      type: 'index_chunk',
      requestId: req,
      root: '/proj',
      entries: [entry('src/a.ts'), entry('src/b.ts')],
      complete: true,
    });
    expect(model.root).toBe('/proj');
    expect(model.state.kind).toBe('loaded');
    expect(model.entries.map((e) => e.path)).toEqual([
      'src',
      'src/a.ts',
      'src/b.ts',
    ]);
  });

  it('ignores blank paths and skips a redundant re-index', () => {
    const { model, client } = setup();
    model.index('  ');
    expect(client.sent).toHaveLength(0);
    model.index('/proj');
    const req = lastReq(client);
    model.handle({
      type: 'index_chunk',
      requestId: req,
      root: '/proj',
      entries: [],
      complete: true,
    });
    client.sent.length = 0;
    model.index('/proj');
    expect(client.sent).toHaveLength(0);
    // refresh bypasses the cache.
    model.index('/proj', true);
    expect(client.sent).toHaveLength(1);
  });

  it('ignores chunks/failures for superseded requests', () => {
    const { model } = setup();
    model.index('/proj');
    model.handle({
      type: 'index_chunk',
      requestId: 'stale',
      root: '/x',
      entries: [entry('y')],
      complete: true,
    });
    model.handle({ type: 'index_failed', requestId: 'stale', message: 'no' });
    expect(model.state.kind).toBe('loading');
  });

  it('surfaces an index failure', () => {
    const { model, client } = setup();
    model.index('/proj');
    model.handle({ type: 'index_failed', requestId: lastReq(client), message: 'boom' });
    expect(model.state).toEqual({ kind: 'error', message: 'boom' });
  });

  it('exposes the showHidden flag', () => {
    const { model } = setup();
    expect(model.showHidden).toBe(false);
    model.setShowHidden(true);
    expect(model.showHidden).toBe(true);
  });

  it('returns sorted, filtered children of a directory', () => {
    const { model, client } = setup();
    model.index('/proj');
    model.handle({
      type: 'index_chunk',
      requestId: lastReq(client),
      root: '/proj',
      entries: [
        entry('z.ts'),
        entry('src', true),
        entry('a.ts'),
        entry('.hidden'),
        entry('src/deep/x.ts'),
        entry('docs', true),
      ],
      complete: true,
    });
    expect(model.children('').map((e) => e.path)).toEqual([
      'docs',
      'src',
      'a.ts',
      'z.ts',
    ]);
    model.setShowHidden(true);
    expect(model.children('').map((e) => e.path)).toContain('.hidden');
    model.setShowHidden(true); // no-op branch
    expect(model.children('src')).toEqual([]);
  });

  it('ignores unrelated messages', () => {
    const { model } = setup();
    let fired = 0;
    model.subscribe(() => fired++);
    model.handle({ type: 'error', message: 'x' });
    expect(fired).toBe(0);
  });
});
