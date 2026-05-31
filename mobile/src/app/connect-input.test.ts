import { DEFAULT_PORT, parseManualTarget } from './connect-input';

describe('parseManualTarget', () => {
  it('parses host with explicit port and token', () => {
    const r = parseManualTarget('mac.ts.net', '9000', 'tok');
    expect(r.ok).toBe(true);
    expect(r.target).toEqual({ host: 'mac.ts.net', port: 9000, token: 'tok' });
  });

  it('defaults the port when empty', () => {
    const r = parseManualTarget('mac.ts.net', '  ', '');
    expect(r.target).toEqual({ host: 'mac.ts.net', port: DEFAULT_PORT });
  });

  it('extracts host:port when the port field is empty', () => {
    const r = parseManualTarget('mac.ts.net:7777', '', '');
    expect(r.target).toEqual({ host: 'mac.ts.net', port: 7777 });
  });

  it('prefers the explicit port field over an embedded colon', () => {
    const r = parseManualTarget('mac.ts.net:7777', '8888', '');
    expect(r.target).toEqual({ host: 'mac.ts.net', port: 8888 });
  });

  it('rejects an empty host', () => {
    const r = parseManualTarget('   ', '8765', '');
    expect(r.ok).toBe(false);
    expect(r.error).toMatch(/address/);
  });

  it('rejects out-of-range and non-integer ports', () => {
    expect(parseManualTarget('h', '70000', '').ok).toBe(false);
    expect(parseManualTarget('h', '0', '').ok).toBe(false);
    expect(parseManualTarget('h', 'abc', '').ok).toBe(false);
  });

  it('does not split an IPv6-bracketed host before the closing bracket', () => {
    const r = parseManualTarget('[fe80::1]', '8765', '');
    expect(r.ok).toBe(true);
    expect(r.target).toEqual({ host: '[fe80::1]', port: 8765 });
  });

  it('trims a blank token to undefined', () => {
    const r = parseManualTarget('h', '1', '   ');
    expect(r.target?.token).toBeUndefined();
  });
});
