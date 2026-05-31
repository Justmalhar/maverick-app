import { safetyNumber, shortFingerprint } from './safety-number';

describe('safetyNumber', () => {
  it('renders five six-digit groups deterministically', () => {
    const key = new Uint8Array(32).fill(7);
    const sn = safetyNumber(key);
    const groups = sn.split(' ');
    expect(groups).toHaveLength(5);
    for (const g of groups) expect(g).toMatch(/^\d{6}$/);
    expect(safetyNumber(key)).toBe(sn); // stable
  });

  it('differs for different keys', () => {
    const a = safetyNumber(new Uint8Array(32).fill(1));
    const b = safetyNumber(new Uint8Array(32).fill(2));
    expect(a).not.toBe(b);
  });
});

describe('shortFingerprint', () => {
  it('renders 8 uppercase hex chars', () => {
    const fp = shortFingerprint(new Uint8Array(32).fill(0xab));
    expect(fp).toMatch(/^[0-9A-F]{8}$/);
  });
});
