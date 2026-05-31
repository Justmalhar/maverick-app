import { ConnectionHistory, hostDisplayName, SavedHost } from './connection-history';
import { MemoryStore } from './storage';

function makeHistory(now = () => 1000): {
  store: MemoryStore;
  history: ConnectionHistory;
} {
  const store = new MemoryStore();
  return { store, history: new ConnectionHistory(store, now) };
}

describe('hostDisplayName', () => {
  it('prefers name, falls back to host:port', () => {
    const base: SavedHost = {
      id: '1',
      name: '',
      host: 'mac.ts.net',
      port: 8765,
      lastConnected: 0,
    };
    expect(hostDisplayName(base)).toBe('mac.ts.net:8765');
    expect(hostDisplayName({ ...base, name: 'Studio' })).toBe('Studio');
  });
});

describe('ConnectionHistory', () => {
  it('records a new host with name/token/pinnedKey', () => {
    const { history } = makeHistory();
    history.record('mac.local', 8765, {
      name: 'Studio',
      token: 'secret',
      pinnedKey: 'AAA',
    });
    expect(history.hosts).toHaveLength(1);
    const h = history.hosts[0]!;
    expect(h.host).toBe('mac.local');
    expect(h.name).toBe('Studio');
    expect(h.token).toBe('secret');
    expect(h.pinnedKey).toBe('AAA');
  });

  it('records a bare host without optional fields', () => {
    const { history } = makeHistory();
    history.record('mac.local', 8765);
    const h = history.hosts[0]!;
    expect(h.name).toBe('');
    expect(h.token).toBeUndefined();
    expect(h.pinnedKey).toBeUndefined();
  });

  it('ignores an empty host', () => {
    const { history } = makeHistory();
    history.record('   ', 8765);
    expect(history.hosts).toHaveLength(0);
  });

  it('upserts by host+port, bumping recency and merging fields', () => {
    let t = 1000;
    const { history } = makeHistory(() => t);
    history.record('mac.local', 8765, { name: 'A' });
    t = 2000;
    history.record('mac.local', 8765, { name: 'B', token: 'tok', pinnedKey: 'K' });
    expect(history.hosts).toHaveLength(1);
    const h = history.hosts[0]!;
    expect(h.lastConnected).toBe(2000);
    expect(h.name).toBe('B');
    expect(h.token).toBe('tok');
    expect(h.pinnedKey).toBe('K');
  });

  it('does not clobber name/token with empty values on re-record', () => {
    const { history } = makeHistory();
    history.record('mac.local', 8765, { name: 'A', token: 'tok' });
    history.record('mac.local', 8765, {});
    const h = history.hosts[0]!;
    expect(h.name).toBe('A');
    expect(h.token).toBe('tok');
  });

  it('sorts by recency descending and finds by host+port', () => {
    let t = 1000;
    const { history } = makeHistory(() => t);
    history.record('a', 1);
    t = 5000;
    history.record('b', 2);
    expect(history.sortedByRecency.map((h) => h.host)).toEqual(['b', 'a']);
    expect(history.find('a', 1)?.host).toBe('a');
    expect(history.find('zzz', 9)).toBeUndefined();
  });

  it('renames and removes entries', () => {
    const { history } = makeHistory();
    history.record('a', 1);
    const id = history.hosts[0]!.id;
    history.rename(id, 'Renamed');
    expect(history.hosts[0]!.name).toBe('Renamed');
    history.rename('nope', 'x');
    history.remove('nope');
    expect(history.hosts).toHaveLength(1);
    history.remove(id);
    expect(history.hosts).toHaveLength(0);
  });

  it('persists and reloads from the store', () => {
    const store = new MemoryStore();
    const h1 = new ConnectionHistory(store);
    h1.record('mac.local', 8765, { name: 'Studio' });
    const h2 = new ConnectionHistory(store);
    expect(h2.hosts).toHaveLength(1);
    expect(h2.hosts[0]!.name).toBe('Studio');
  });

  it('ignores corrupt or non-array persisted payloads', () => {
    const store = new MemoryStore();
    store.setString('savedHosts.v2', 'not json{');
    expect(new ConnectionHistory(store).hosts).toHaveLength(0);
    store.setString('savedHosts.v2', '{"not":"array"}');
    expect(new ConnectionHistory(store).hosts).toHaveLength(0);
  });

  it('filters out malformed entries on load', () => {
    const store = new MemoryStore();
    store.setString(
      'savedHosts.v2',
      JSON.stringify([
        { id: '1', name: '', host: 'ok', port: 1, lastConnected: 0 },
        { id: 2, host: 'bad' },
        null,
        'string',
      ]),
    );
    const h = new ConnectionHistory(store);
    expect(h.hosts).toHaveLength(1);
    expect(h.hosts[0]!.host).toBe('ok');
  });

  it('notifies subscribers on save', () => {
    const { history } = makeHistory();
    let fired = 0;
    history.subscribe(() => fired++);
    history.record('a', 1);
    expect(fired).toBe(1);
  });
});
