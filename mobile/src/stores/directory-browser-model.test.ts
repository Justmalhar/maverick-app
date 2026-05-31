import {
  defaultTimer,
  DirectoryBrowserModel,
  LRUCache,
} from './directory-browser-model';
import { FakeClient } from '@/test/fixtures';
import { DirectoryEntry } from '@/protocol';

function dir(name: string, isDirectory = true, isHidden = false): DirectoryEntry {
  return { name, isDirectory, isHidden };
}

function lastReq(client: FakeClient): string {
  return (client.last() as { requestId: string }).requestId;
}

describe('LRUCache', () => {
  it('evicts the least-recently-used entry past capacity', () => {
    const c = new LRUCache<string, number>(2);
    c.set('a', 1);
    c.set('b', 2);
    expect(c.get('a')).toBe(1); // bump a
    c.set('c', 3); // evicts b (LRU)
    expect(c.get('b')).toBeUndefined();
    expect(c.get('a')).toBe(1);
    expect(c.get('c')).toBe(3);
    expect(c.size).toBe(2);
  });

  it('updates an existing key without growing', () => {
    const c = new LRUCache<string, number>(2);
    c.set('a', 1);
    c.set('a', 9);
    expect(c.get('a')).toBe(9);
    expect(c.size).toBe(1);
    expect(c.get('missing')).toBeUndefined();
  });
});

describe('DirectoryBrowserModel', () => {
  function setup(now = () => 1000): {
    model: DirectoryBrowserModel;
    client: FakeClient;
    timers: Array<{ fn: () => void; delay: number }>;
  } {
    const client = new FakeClient();
    const timers: Array<{ fn: () => void; delay: number }> = [];
    const model = new DirectoryBrowserModel(client.asClient(), now, (fn, delay) => {
      timers.push({ fn, delay });
      return timers.length;
    });
    return { model, client, timers };
  }

  it('navigates and loads a listing', () => {
    const { model, client } = setup();
    model.navigate('/proj');
    expect(model.state.kind).toBe('loading');
    const req = lastReq(client);
    model.handle({
      type: 'directory_listing',
      requestId: req,
      path: '/proj',
      entries: [dir('a'), dir('.git', true, true)],
    });
    expect(model.currentPath).toBe('/proj');
    expect(model.entries.map((e) => e.name)).toEqual(['a']);
    expect(model.state.kind).toBe('loaded');
  });

  it('serves a fresh cache hit without a round-trip', () => {
    let t = 1000;
    const { model, client } = setup(() => t);
    model.navigate('/proj');
    model.handle({
      type: 'directory_listing',
      requestId: lastReq(client),
      path: '/proj',
      entries: [dir('a')],
    });
    client.sent.length = 0;
    t = 1000 + 10_000; // within 30s TTL
    model.navigate('/proj');
    expect(client.sent).toHaveLength(0);
    expect(model.state.kind).toBe('loaded');
  });

  it('refetches a stale cache entry', () => {
    let t = 1000;
    const { model, client } = setup(() => t);
    model.navigate('/proj');
    model.handle({
      type: 'directory_listing',
      requestId: lastReq(client),
      path: '/proj',
      entries: [dir('a')],
    });
    client.sent.length = 0;
    t = 1000 + 40_000; // past 30s TTL
    model.navigate('/proj');
    expect(client.sent).toHaveLength(1);
  });

  it('normalises an empty/whitespace path to home', () => {
    const { model, client } = setup();
    model.navigate('   ');
    expect(client.last()).toEqual({
      type: 'list_directory',
      requestId: lastReq(client),
    });
    model.navigate(null);
    expect((client.last() as { path?: string }).path).toBeUndefined();
  });

  it('errors immediately when disconnected', () => {
    const { model, client } = setup();
    client.connectedState = 'disconnected';
    model.navigate('/proj');
    expect(model.state.kind).toBe('error');
    expect(client.sent).toHaveLength(0);
  });

  it('times out a stuck request', () => {
    const { model, timers } = setup();
    model.navigate('/proj');
    expect(timers).toHaveLength(1);
    expect(timers[0]!.delay).toBe(8000);
    timers[0]!.fn();
    expect(model.state).toEqual({
      kind: 'error',
      message: 'Request timed out. Pull down to retry.',
    });
  });

  it('does not error if the reply arrived before the timeout fires', () => {
    const { model, client, timers } = setup();
    model.navigate('/proj');
    model.handle({
      type: 'directory_listing',
      requestId: lastReq(client),
      path: '/proj',
      entries: [],
    });
    timers[0]!.fn();
    expect(model.state.kind).toBe('loaded');
  });

  it('navigates up to the parent and to root', () => {
    const { model, client } = setup();
    model.navigate('/a/b/c');
    model.handle({
      type: 'directory_listing',
      requestId: lastReq(client),
      path: '/a/b/c',
      entries: [],
    });
    client.sent.length = 0;
    model.navigateUp();
    expect((client.last() as { path: string }).path).toBe('/a/b');
    model.handle({
      type: 'directory_listing',
      requestId: lastReq(client),
      path: '/a',
      entries: [],
    });
    model.navigateUp(); // /a -> /
    expect((client.last() as { path: string }).path).toBe('/');
  });

  it('caches prefetch listings silently and ignores their nav state', () => {
    const { model, client } = setup();
    model.preflight();
    const req = lastReq(client);
    model.handle({
      type: 'directory_listing',
      requestId: req,
      path: '/home',
      entries: [dir('a')],
    });
    // Prefetch did not change visible state.
    expect(model.currentPath).toBe('');
    // But it populated the cache: navigating there is now a cache hit.
    client.sent.length = 0;
    model.navigate('/home');
    expect(client.sent).toHaveLength(0);
    expect(model.currentPath).toBe('/home');
  });

  it('ignores a prefetch failure and a stale failure', () => {
    const { model } = setup();
    model.preflight();
    model.handle({
      type: 'directory_listing_failed',
      requestId: 'req-1',
      message: 'x',
    });
    expect(model.state.kind).toBe('idle');
    model.handle({
      type: 'directory_listing_failed',
      requestId: 'stale',
      message: 'y',
    });
    expect(model.state.kind).toBe('idle');
  });

  it('surfaces a listing failure for the visible request', () => {
    const { model, client } = setup();
    model.navigate('/proj');
    model.handle({
      type: 'directory_listing_failed',
      requestId: lastReq(client),
      message: 'denied',
    });
    expect(model.state).toEqual({ kind: 'error', message: 'denied' });
  });

  it('ignores a directory_listing for a superseded request but still caches it', () => {
    const { model, client } = setup();
    model.navigate('/proj');
    model.handle({
      type: 'directory_listing',
      requestId: 'stale',
      path: '/other',
      entries: [dir('z')],
    });
    expect(model.currentPath).toBe('');
    // The cached /other is reachable.
    client.sent.length = 0;
    model.navigate('/other');
    expect(client.sent).toHaveLength(0);
  });

  it('toggles the hidden filter and recomputes', () => {
    const { model, client } = setup();
    model.navigate('/proj');
    model.handle({
      type: 'directory_listing',
      requestId: lastReq(client),
      path: '/proj',
      entries: [dir('a'), dir('.h', true, true)],
    });
    expect(model.entries).toHaveLength(1);
    model.setShowHidden(true);
    expect(model.entries).toHaveLength(2);
    model.setShowHidden(true); // no-op
    expect(model.showHidden).toBe(true);
  });

  it('ignores unrelated messages', () => {
    const { model } = setup();
    let fired = 0;
    model.subscribe(() => fired++);
    model.handle({ type: 'error', message: 'x' });
    expect(fired).toBe(0);
  });

  it('defaultTimer schedules via setTimeout', () => {
    jest.useFakeTimers();
    try {
      const fn = jest.fn();
      defaultTimer(fn, 8000);
      expect(fn).not.toHaveBeenCalled();
      jest.advanceTimersByTime(8000);
      expect(fn).toHaveBeenCalledTimes(1);
    } finally {
      jest.useRealTimers();
    }
  });

  it('uses the wall-clock default for cache timestamps', () => {
    const client = new FakeClient();
    // Default `now` (Date.now), but a no-op timer so the 8s timeout cannot leak.
    const model = new DirectoryBrowserModel(client.asClient(), undefined, () => 0);
    model.navigate('/proj');
    expect(model.state.kind).toBe('loading');
    const req = (client.last() as { requestId: string }).requestId;
    // Handling a listing stamps the cache via the default now().
    model.handle({
      type: 'directory_listing',
      requestId: req,
      path: '/proj',
      entries: [],
    });
    // Immediately re-navigating hits the fresh cache (TTL check uses now()).
    client.sent.length = 0;
    model.navigate('/proj');
    expect(client.sent).toHaveLength(0);
    expect(model.state.kind).toBe('loaded');
  });
});
