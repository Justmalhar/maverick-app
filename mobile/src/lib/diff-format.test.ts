import { parseDiff } from './diff-format';

describe('parseDiff', () => {
  it('classifies every line kind and tallies adds/removes', () => {
    const diff = [
      'diff --git a/x b/x',
      'index 111..222 100644',
      '--- a/x',
      '+++ b/x',
      '@@ -1,2 +1,2 @@',
      ' context',
      '-removed',
      '+added',
    ].join('\n');
    const parsed = parseDiff(diff);
    expect(parsed.added).toBe(1);
    expect(parsed.removed).toBe(1);
    expect(parsed.lines.map((l) => l.kind)).toEqual([
      'meta',
      'meta',
      'meta',
      'meta',
      'hunk',
      'context',
      'remove',
      'add',
    ]);
  });

  it('returns no lines for an empty diff', () => {
    expect(parseDiff('')).toEqual({ lines: [], added: 0, removed: 0 });
  });

  it('treats a blank line as context', () => {
    const parsed = parseDiff('\n');
    expect(parsed.lines.map((l) => l.kind)).toEqual(['context', 'context']);
  });
});
