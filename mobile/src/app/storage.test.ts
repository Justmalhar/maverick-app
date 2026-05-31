import { MemoryStore } from './storage';

describe('MemoryStore', () => {
  it('stores, reads, removes, and snapshots entries', () => {
    const s = new MemoryStore();
    expect(s.getString('k')).toBeUndefined();
    s.setString('k', 'v');
    expect(s.getString('k')).toBe('v');
    s.setString('k2', 'v2');
    expect(s.entries()).toEqual([
      ['k', 'v'],
      ['k2', 'v2'],
    ]);
    s.remove('k');
    expect(s.getString('k')).toBeUndefined();
    expect(s.entries()).toEqual([['k2', 'v2']]);
  });
});
