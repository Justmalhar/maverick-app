/**
 * Terminal scrollback model for the RN terminal view. The server sends terminal
 * bytes as base64 under `output` / `scrollback`. We decode to UTF-8 text,
 * append to a line-oriented ring buffer capped at 4000 lines (the Swift/desktop
 * scrollback cap), and emit the freshly-decoded chunk so the host webview can
 * `term.write()` it incrementally without re-rendering the whole buffer.
 *
 * The OSC-7 cwd escape (`\x1b]7;file://host/path\x1b\\` or BEL-terminated) is
 * parsed out and surfaced via `onCwd` so the Files/Diff tabs can re-root,
 * matching the desktop's live-cwd behaviour.
 */

import { decodeBase64 } from '@/protocol/primitives';

export const SCROLLBACK_LINE_CAP = 4000;

const decoder = new TextDecoder();

/** OSC 7: ESC ] 7 ; <uri> (ST = ESC \ or BEL). */
const OSC7_RE = /\x1b\]7;file:\/\/[^/]*([^\x07\x1b]*)(?:\x07|\x1b\\)/g;

export interface TerminalChunk {
  /** Decoded text to write into xterm. */
  text: string;
  /** cwd parsed from an OSC-7 sequence in this chunk, if any. */
  cwd?: string;
}

export class TerminalBuffer {
  private lines: string[] = [''];

  /** Decode a base64 frame, extract OSC-7 cwd, append to the ring, return it. */
  ingest(base64Data: string): TerminalChunk {
    let bytes: Uint8Array;
    try {
      bytes = decodeBase64(base64Data);
    } catch {
      // Some servers (and the TS codec path) deliver plain text rather than
      // base64; fall back to encoding the string's UTF-16 as-is.
      return this.append(base64Data, undefined);
    }
    const text = decoder.decode(bytes);
    const cwd = extractCwd(text);
    return this.append(text, cwd);
  }

  private append(text: string, cwd: string | undefined): TerminalChunk {
    const segments = text.split('\n');
    for (let i = 0; i < segments.length; i++) {
      if (i > 0) this.lines.push('');
      this.lines[this.lines.length - 1] += segments[i]!;
    }
    if (this.lines.length > SCROLLBACK_LINE_CAP) {
      this.lines = this.lines.slice(this.lines.length - SCROLLBACK_LINE_CAP);
    }
    const chunk: TerminalChunk = { text };
    if (cwd !== undefined) chunk.cwd = cwd;
    return chunk;
  }

  get lineCount(): number {
    return this.lines.length;
  }

  /** The full resident scrollback as one string (used to seed a fresh webview). */
  snapshot(): string {
    return this.lines.join('\n');
  }

  clear(): void {
    this.lines = [''];
  }
}

function extractCwd(text: string): string | undefined {
  let match: RegExpExecArray | null;
  let last: string | undefined;
  OSC7_RE.lastIndex = 0;
  while ((match = OSC7_RE.exec(text)) !== null) {
    const path = decodeURIComponent(match[1]!);
    if (path.length > 0) last = path;
  }
  return last;
}
