/**
 * Read-only git diff browser. Lists changed files from git_status; tapping a
 * file fetches + shows its colourised unified diff (git_diff). All parsing is
 * in diff-format / the GitStatusModel.
 */
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useApp } from '../AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { parseDiff } from '@/lib/diff-format';
import { space, theme } from '../theme';
import { Mono } from '../ui/Surface';

const LINE_COLORS = {
  add: theme.success,
  remove: theme.danger,
  hunk: theme.info,
  meta: theme.textTertiary,
  context: theme.textSecondary,
} as const;

export function GitDiffView({ repoPath }: { repoPath: string }): React.JSX.Element {
  const app = useApp();
  const status = useObservable(app.git, (g) => g.status);
  const state = useObservable(app.git, (g) => g.state);
  const [selected, setSelected] = useState<string | null>(null);
  // Re-render when the diff for the selected file lands (separate subscription
  // because `status`/`state` don't change on a diff result).
  const selectedDiff = useObservable(app.git, (g) =>
    selected !== null ? g.diff(selected, false) : undefined,
  );

  useEffect(() => {
    if (repoPath.length > 0) app.git.refresh(repoPath);
  }, [app, repoPath]);

  const openDiff = (file: string, staged: boolean): void => {
    setSelected(file);
    app.git.fetchDiff(file, staged);
  };

  return (
    <View style={styles.root}>
      {state.kind === 'error' && (
        <Mono color={theme.danger} style={styles.pad}>
          {state.message}
        </Mono>
      )}
      {!status.isRepo && state.kind === 'loaded' && (
        <Mono color={theme.textSecondary} style={styles.pad}>
          Not a git repository.
        </Mono>
      )}
      {status.branch !== undefined && (
        <Mono color={theme.textSecondary} size={12} style={styles.pad}>
          {status.branch} · {status.ahead}↑ {status.behind}↓
        </Mono>
      )}
      <ScrollView>
        {status.files.map((f) => (
          <Pressable
            key={`${f.staged ? 'S' : 'U'}:${f.path}`}
            accessibilityRole="button"
            onPress={() => openDiff(f.path, f.staged)}
            style={styles.fileRow}
          >
            <Mono color={theme.warning} size={12} weight="700">
              {f.status}
            </Mono>
            <Mono color={theme.textPrimary} size={12} numberOfLines={1}>
              {f.path}
            </Mono>
          </Pressable>
        ))}
        {selectedDiff !== undefined && (
          <View style={styles.diff} testID="diff-body">
            {parseDiff(selectedDiff.text).lines.map((l, i) => (
              <Mono key={i} color={LINE_COLORS[l.kind]} size={11}>
                {l.text}
              </Mono>
            ))}
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  pad: { padding: space.md },
  fileRow: {
    flexDirection: 'row',
    gap: space.sm,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: theme.stroke,
  },
  diff: { padding: space.md, backgroundColor: theme.bgElevated },
});
