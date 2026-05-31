/**
 * The agent chat screen. Renders the AgentSessionModel timeline bottom-anchored,
 * an input bar (agent_input), a permission prompt overlay (allow/deny via
 * permission_response), and lazy history paging (prepend-older on scroll-to-top
 * via onEndReached with an inverted list).
 *
 * The list is inverted so index 0 is the newest item and the bottom-anchored
 * tail stays pinned; scrolling up triggers `onLoadOlder`.
 */
import { useCallback, useMemo, useState } from 'react';
import {
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  TextInput,
  View,
} from 'react-native';
import { AgentChatItem, AgentSessionModel } from '@/stores/agent-session-model';
import { useApp } from '../AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { AgentMessageRow } from './AgentMessageRow';
import { radius, space, theme } from '../theme';
import { Mono } from '../ui/Surface';

export function AgentChatView({
  model,
  onLoadOlder,
}: {
  model: AgentSessionModel;
  onLoadOlder?: () => void;
}): React.JSX.Element {
  const app = useApp();
  const items = useObservable(model, (m) => m.items);
  const pending = useObservable(model, (m) => m.pendingPermission);
  const thinking = useObservable(model, (m) => m.isThinking);
  const [draft, setDraft] = useState('');

  // The list is `inverted`, so it consumes newest-first. Reverse only when the
  // timeline identity changes — a fresh array every render breaks FlatList's
  // data-stability check and causes scroll jank.
  const reversed = useMemo(() => [...items].reverse(), [items]);

  const send = useCallback(() => {
    const text = draft.trim();
    if (text.length === 0) return;
    app.client.agentInput(model.sessionId, text);
    setDraft('');
  }, [app, draft, model.sessionId]);

  const respond = useCallback(
    (allowed: boolean) => {
      if (pending === null) return;
      app.client.respondToPermission(model.sessionId, pending.requestId, allowed);
      model.resolvePermission(pending.requestId);
    },
    [app, model, pending],
  );

  const renderItem = useCallback(
    ({ item }: { item: AgentChatItem }) => (
      <AgentMessageRow item={item} onToggleBatch={(id) => model.toggleBatch(id)} />
    ),
    [model],
  );

  return (
    <KeyboardAvoidingView
      style={styles.root}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <FlatList
        inverted
        data={reversed}
        keyExtractor={(i) => i.id}
        renderItem={renderItem}
        onEndReached={onLoadOlder}
        onEndReachedThreshold={0.4}
        contentContainerStyle={styles.list}
        testID="agent-timeline"
      />
      {thinking && (
        <Mono color={theme.textSecondary} size={12} style={styles.thinking}>
          working…
        </Mono>
      )}
      {pending !== null && (
        <View style={styles.permissionBar} testID="permission-bar">
          <Mono color={theme.warning} size={12} weight="700">
            Allow {pending.tool}?
          </Mono>
          <View style={styles.permissionButtons}>
            <Pressable
              accessibilityRole="button"
              onPress={() => respond(false)}
              style={[styles.permBtn, styles.deny]}
            >
              <Mono color={theme.danger} weight="700">
                Deny
              </Mono>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              onPress={() => respond(true)}
              style={[styles.permBtn, styles.allow]}
            >
              <Mono color={theme.onAccent} weight="700">
                Allow
              </Mono>
            </Pressable>
          </View>
        </View>
      )}
      <View style={styles.inputBar}>
        <TextInput
          style={styles.input}
          value={draft}
          onChangeText={setDraft}
          placeholder="Message the agent…"
          placeholderTextColor={theme.textTertiary}
          multiline
          testID="agent-input"
        />
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Send"
          onPress={send}
          style={styles.sendBtn}
        >
          <Mono color={theme.onAccent} weight="700">
            ↑
          </Mono>
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  list: { padding: space.md, gap: space.xs },
  thinking: { paddingHorizontal: space.md, paddingBottom: space.xs },
  permissionBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: space.md,
    backgroundColor: 'rgba(250,204,21,0.08)',
    borderTopWidth: 1,
    borderColor: theme.warning,
  },
  permissionButtons: { flexDirection: 'row', gap: space.sm },
  permBtn: {
    paddingHorizontal: space.lg,
    paddingVertical: space.sm,
    borderRadius: radius.pill,
  },
  deny: { backgroundColor: 'rgba(248,113,113,0.12)' },
  allow: { backgroundColor: theme.accent },
  inputBar: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    padding: space.sm,
    gap: space.sm,
    borderTopWidth: 1,
    borderColor: theme.stroke,
    backgroundColor: theme.bgElevated,
  },
  input: {
    flex: 1,
    color: theme.textPrimary,
    maxHeight: 120,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
    backgroundColor: theme.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: theme.stroke,
  },
  sendBtn: {
    width: 40,
    height: 40,
    borderRadius: radius.pill,
    backgroundColor: theme.accent,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
