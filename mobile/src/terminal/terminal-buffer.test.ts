import { SCROLLBACK_LINE_CAP, TerminalBuffer } from './terminal-buffer';
import { encodeBase64 } from '@/protocol/primitives';

function b64(s: string): string {
  return encodeBase64(new TextEncoder().encode(s));
}

describe('TerminalBuffer', () => {
  it('decodes base64 frames and accumulates lines', () => {
    const buf = new TerminalBuffer();
    const chunk = buf.ingest(b64('line1\nline2'));
    expect(chunk.text).toBe('line1\nline2');
    expect(buf.lineCount).toBe(2);
    buf.ingest(b64(' more'));
    expect(buf.snapshot()).toBe('line1\nline2 more');
  });

  it('falls back to raw text when input is not valid base64', () => {
    const buf = new TerminalBuffer();
    const chunk = buf.ingest('not%%%base64');
    expect(chunk.text).toBe('not%%%base64');
  });

  it('extracts the cwd from an OSC-7 sequence (BEL terminated)', () => {
    const buf = new TerminalBuffer();
    const chunk = buf.ingest(b64('\x1b]7;file://host/Users/me/proj\x07$ '));
    expect(chunk.cwd).toBe('/Users/me/proj');
  });

  it('extracts the cwd from an OSC-7 sequence (ST terminated) and decodes %20', () => {
    const buf = new TerminalBuffer();
    const chunk = buf.ingest(b64('\x1b]7;file://host/a%20b\x1b\\'));
    expect(chunk.cwd).toBe('/a b');
  });

  it('uses the last OSC-7 cwd when several appear and skips empty paths', () => {
    const buf = new TerminalBuffer();
    const chunk = buf.ingest(
      b64('\x1b]7;file://h/\x07\x1b]7;file://h/final\x07'),
    );
    expect(chunk.cwd).toBe('/final');
  });

  it('reports no cwd when there is no OSC-7 sequence', () => {
    const buf = new TerminalBuffer();
    expect(buf.ingest(b64('plain')).cwd).toBeUndefined();
  });

  it('ignores an OSC-7 sequence with an empty path', () => {
    const buf = new TerminalBuffer();
    // file://host with no path → empty capture, must not set cwd.
    expect(buf.ingest(b64('\x1b]7;file://host\x07prompt')).cwd).toBeUndefined();
  });

  it('caps the scrollback at the line limit', () => {
    const buf = new TerminalBuffer();
    const lines = Array.from({ length: SCROLLBACK_LINE_CAP + 50 }, (_, i) => `l${i}`);
    buf.ingest(b64(lines.join('\n')));
    expect(buf.lineCount).toBe(SCROLLBACK_LINE_CAP);
    expect(buf.snapshot().split('\n')[0]).toBe('l50');
  });

  it('clears back to a single empty line', () => {
    const buf = new TerminalBuffer();
    buf.ingest(b64('a\nb'));
    buf.clear();
    expect(buf.lineCount).toBe(1);
    expect(buf.snapshot()).toBe('');
  });
});
