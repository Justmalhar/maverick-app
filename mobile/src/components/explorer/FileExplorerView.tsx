/**
 * Read-only project file explorer. Indexes the project (index_project) then
 * shows a one-level tree the user can drill into. Tree derivation lives in the
 * ProjectIndexModel.
 */
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useApp } from '../AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { space, theme } from '../theme';
import { Mono } from '../ui/Surface';

export function FileExplorerView({
  rootPath,
}: {
  rootPath: string;
}): React.JSX.Element {
  const app = useApp();
  const state = useObservable(app.index, (i) => i.state);
  // Re-render whenever entries change.
  useObservable(app.index, (i) => i.entries);
  const [dir, setDir] = useState('');

  useEffect(() => {
    if (rootPath.length > 0) app.index.index(rootPath);
  }, [app, rootPath]);

  const children = app.index.children(dir);

  return (
    <View style={styles.root}>
      <View style={styles.crumbBar}>
        {dir.length > 0 && (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Up"
            onPress={() => {
              const idx = dir.lastIndexOf('/');
              setDir(idx > 0 ? dir.slice(0, idx) : '');
            }}
          >
            <Mono color={theme.info} size={12}>
              .. /{dir}
            </Mono>
          </Pressable>
        )}
      </View>
      {state.kind === 'error' && (
        <Mono color={theme.danger} style={styles.pad}>
          {state.message}
        </Mono>
      )}
      <ScrollView>
        {children.map((e) => {
          const leaf = e.path.split('/').pop()!;
          return (
            <Pressable
              key={e.path}
              accessibilityRole="button"
              onPress={() => {
                if (e.isDirectory) setDir(e.path);
              }}
              style={styles.row}
            >
              <Mono color={theme.textSecondary} size={13}>
                {e.isDirectory ? '📁' : '📄'}
              </Mono>
              <Mono color={theme.textPrimary} size={13} numberOfLines={1}>
                {leaf}
              </Mono>
            </Pressable>
          );
        })}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  crumbBar: { padding: space.sm },
  pad: { padding: space.md },
  row: {
    flexDirection: 'row',
    gap: space.sm,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: theme.stroke,
  },
});
