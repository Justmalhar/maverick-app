/**
 * Session picker — the WhatsApp-style handoff entry point. Lists agent and
 * terminal sessions (from session.list), with Resume (agent → chat mode) and
 * Attach actions, then routes into the workspace.
 */
import { useEffect } from 'react';
import { Pressable, SectionList, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useApp } from '@/components/AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { useConnectionState } from '@/hooks/useConnectionState';
import { PickerRow } from '@/stores/session-picker';
import { space, theme } from '@/components/theme';
import { Mono } from '@/components/ui/Surface';

export function SessionsScreen(): React.JSX.Element {
  const app = useApp();
  const router = useRouter();
  const connState = useConnectionState(app.client);
  useObservable(app.sessions, (s) => s.sessions);

  useEffect(() => {
    app.picker.refresh();
  }, [app]);

  const open = (row: PickerRow, resume: boolean): void => {
    if (resume) app.picker.resume(row.session.id);
    else app.picker.attach(row.session.id);
    router.push(`/workspace?sessionId=${row.session.id}`);
  };

  const sections = [
    { title: 'Agents', data: app.picker.agents() },
    { title: 'Terminals', data: app.picker.terminals() },
  ].filter((s) => s.data.length > 0);

  return (
    <View style={styles.root}>
      <View style={styles.header}>
        <Mono size={20} weight="700">
          Sessions
        </Mono>
        <Mono color={connState === 'connected' ? theme.success : theme.warning} size={11}>
          {connState}
        </Mono>
      </View>
      <SectionList
        sections={sections}
        keyExtractor={(row) => row.session.id}
        renderSectionHeader={({ section }) => (
          <Mono color={theme.textSecondary} size={12} weight="600" style={styles.sectionHeader}>
            {section.title}
          </Mono>
        )}
        renderItem={({ item }) => (
          <View style={styles.row}>
            <Pressable
              accessibilityRole="button"
              style={styles.rowMain}
              onPress={() => open(item, item.resumable)}
            >
              <Mono weight="600">{item.session.name}</Mono>
              <Mono color={theme.textSecondary} size={11}>
                {item.session.agentProvider ?? item.session.shell}
              </Mono>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={item.resumable ? 'Resume' : 'Attach'}
              onPress={() => open(item, item.resumable)}
              style={styles.action}
            >
              <Mono color={theme.onAccent} size={12} weight="700">
                {item.resumable ? 'Resume' : 'Attach'}
              </Mono>
            </Pressable>
          </View>
        )}
        ListEmptyComponent={
          <Mono color={theme.textSecondary} style={styles.empty}>
            No sessions yet.
          </Mono>
        }
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: space.lg,
  },
  sectionHeader: { paddingHorizontal: space.lg, paddingVertical: space.sm },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: space.lg,
    paddingVertical: space.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: theme.stroke,
  },
  rowMain: { flex: 1, gap: 2 },
  action: {
    backgroundColor: theme.accent,
    borderRadius: 999,
    paddingHorizontal: space.md,
    paddingVertical: space.xs,
  },
  empty: { textAlign: 'center', padding: space.xl },
});
