/**
 * Unified-diff line classification for the GitDiffView. Pure: takes raw diff
 * text and returns typed lines the renderer colours, plus an added/removed
 * tally for the file header.
 */

export type DiffLineKind = 'add' | 'remove' | 'meta' | 'hunk' | 'context';

export interface DiffLine {
  kind: DiffLineKind;
  text: string;
}

export interface ParsedDiff {
  lines: DiffLine[];
  added: number;
  removed: number;
}

export function parseDiff(diff: string): ParsedDiff {
  const out: DiffLine[] = [];
  let added = 0;
  let removed = 0;
  const raw = diff.length === 0 ? [] : diff.split('\n');
  for (const text of raw) {
    let kind: DiffLineKind;
    if (text.startsWith('@@')) {
      kind = 'hunk';
    } else if (
      text.startsWith('+++') ||
      text.startsWith('---') ||
      text.startsWith('diff ') ||
      text.startsWith('index ')
    ) {
      kind = 'meta';
    } else if (text.startsWith('+')) {
      kind = 'add';
      added++;
    } else if (text.startsWith('-')) {
      kind = 'remove';
      removed++;
    } else {
      kind = 'context';
    }
    out.push({ kind, text });
  }
  return { lines: out, added, removed };
}
