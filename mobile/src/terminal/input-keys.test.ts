import {
  byteToString,
  controlSequence,
  ctrlChar,
  ENTER,
  ESC,
  InputKeyState,
  navSequence,
  TAB,
} from './input-keys';

describe('input-keys pure helpers', () => {
  it('maps bytes, nav, and control sequences', () => {
    expect(byteToString(0x03)).toBe('\x03');
    expect(byteToString(0x1ff & 0xff)).toBe(byteToString(0xff));
    expect(navSequence('up')).toBe(ESC + '[A');
    expect(navSequence('pgDn')).toBe(ESC + '[6~');
    expect(navSequence('nope')).toBeUndefined();
    expect(controlSequence('^C')).toBe('\x03');
    expect(controlSequence('^Z')).toBe('\x1a');
    expect(controlSequence('nope')).toBeUndefined();
  });

  it('produces ctrl-letter bytes', () => {
    expect(ctrlChar('c')).toBe('\x03');
    expect(ctrlChar('a')).toBe('\x01');
    expect(ctrlChar('')).toBeUndefined();
  });
});

describe('InputKeyState', () => {
  it('latches and unlatches ctrl', () => {
    const s = new InputKeyState();
    expect(s.isCtrlLatched).toBe(false);
    s.tapCtrl();
    expect(s.isCtrlLatched).toBe(true);
    s.tapCtrl();
    expect(s.isCtrlLatched).toBe(false);
    s.tapCtrl();
    s.clearLatch();
    expect(s.isCtrlLatched).toBe(false);
  });

  it('applies a printable char, honouring the ctrl latch', () => {
    const s = new InputKeyState();
    expect(s.applyChar('a')).toBe('a');
    s.tapCtrl();
    expect(s.applyChar('c')).toBe('\x03');
    expect(s.isCtrlLatched).toBe(false);
  });

  it('returns the char when latched but unmappable', () => {
    const s = new InputKeyState();
    s.tapCtrl();
    expect(s.applyChar('')).toBe('');
    expect(s.isCtrlLatched).toBe(false);
  });

  it('esc/tab/enter clear the latch', () => {
    const s = new InputKeyState();
    s.tapCtrl();
    expect(s.esc()).toBe(ESC);
    expect(s.isCtrlLatched).toBe(false);
    s.tapCtrl();
    expect(s.tab()).toBe(TAB);
    expect(s.isCtrlLatched).toBe(false);
    s.tapCtrl();
    expect(s.enter()).toBe(ENTER);
    expect(s.isCtrlLatched).toBe(false);
  });

  it('nav and control clear the latch and return sequences', () => {
    const s = new InputKeyState();
    s.tapCtrl();
    expect(s.nav('left')).toBe(ESC + '[D');
    expect(s.isCtrlLatched).toBe(false);
    expect(s.nav('bogus')).toBeUndefined();
    s.tapCtrl();
    expect(s.control('^D')).toBe('\x04');
    expect(s.isCtrlLatched).toBe(false);
    expect(s.control('bogus')).toBeUndefined();
  });
});
