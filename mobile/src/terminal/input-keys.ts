/**
 * Keystroke byte sequences for the RN InputToolbar / CursorPad, ported from the
 * Swift `InputToolbar` + `CursorPad`. Pure functions return the exact `input`
 * payload string (raw bytes, latin1-mapped) the server expects, so the thin RN
 * toolbar component only wires taps to `client.input(sessionId, …)`.
 *
 * The control-key latch ("ctrl" then a letter → Ctrl-letter) is modelled by
 * `InputKeyState`, which the component holds and drives via `tapCtrl()` /
 * consuming `applyChar()`.
 */

/** Control bytes for the labelled control keys (^C, ^D, …). */
export const CONTROL_BYTES: Record<string, number> = {
  '^C': 0x03,
  '^D': 0x04,
  '^Z': 0x1a,
  '^L': 0x0c,
  '^A': 0x01,
  '^E': 0x05,
  '^R': 0x12,
  '^W': 0x17,
  '^U': 0x15,
  '^K': 0x0b,
};

/** CSI tails for arrows / navigation. The ESC prefix is added here. */
export const NAV_TAILS: Record<string, string> = {
  up: '[A',
  down: '[B',
  left: '[D',
  right: '[C',
  home: '[H',
  end: '[F',
  pgUp: '[5~',
  pgDn: '[6~',
};

export const ESC = '\x1b';
export const TAB = '\t';
export const ENTER = '\r';

/** Single byte → its 1-char string (latin1 / raw). */
export function byteToString(byte: number): string {
  return String.fromCharCode(byte & 0xff);
}

/** An ESC-prefixed CSI sequence for the given nav key, or undefined if unknown. */
export function navSequence(key: string): string | undefined {
  const tail = NAV_TAILS[key];
  return tail === undefined ? undefined : ESC + tail;
}

/** The control byte string for a labelled control key, or undefined. */
export function controlSequence(label: string): string | undefined {
  const byte = CONTROL_BYTES[label];
  return byte === undefined ? undefined : byteToString(byte);
}

/** Map a single printable character to a Ctrl-<char> byte (mask 0x1f). */
export function ctrlChar(ch: string): string | undefined {
  const code = ch.charCodeAt(0);
  if (Number.isNaN(code)) return undefined;
  return byteToString(code & 0x1f);
}

/**
 * Stateful key helper. Holds the ctrl-latch. `applyChar` returns the bytes to
 * send for a character tap, applying + clearing the latch; nav/esc/tab/enter
 * helpers also clear the latch (matching the Swift toolbar).
 */
export class InputKeyState {
  private ctrlLatched = false;

  get isCtrlLatched(): boolean {
    return this.ctrlLatched;
  }

  tapCtrl(): void {
    this.ctrlLatched = !this.ctrlLatched;
  }

  clearLatch(): void {
    this.ctrlLatched = false;
  }

  /** Bytes for a printable character tap (honours + clears the ctrl latch). */
  applyChar(ch: string): string {
    if (this.ctrlLatched) {
      this.ctrlLatched = false;
      const seq = ctrlChar(ch);
      if (seq !== undefined) return seq;
    }
    this.ctrlLatched = false;
    return ch;
  }

  esc(): string {
    this.ctrlLatched = false;
    return ESC;
  }
  tab(): string {
    this.ctrlLatched = false;
    return TAB;
  }
  enter(): string {
    this.ctrlLatched = false;
    return ENTER;
  }

  /** Nav key (arrow/home/…); clears the latch. Undefined for unknown keys. */
  nav(key: string): string | undefined {
    this.ctrlLatched = false;
    return navSequence(key);
  }

  /** Labelled control sequence (^C, …); clears the latch. */
  control(label: string): string | undefined {
    this.ctrlLatched = false;
    return controlSequence(label);
  }
}
