/**
 * Renders one AgentChatItem. Thin: all derivation lives in the view-model and
 * tool-display helpers. Switches on the item kind to a styled row.
 */
import { Pressable, StyleSheet, View } from 'react-native';
import { AgentChatItem } from '@/stores/agent-session-model';
import { batchSummary, baseName, toolDisplayName, toolFailed } from '@/lib/tool-display';
import { radius, space, theme } from '../theme';
import { Mono } from '../ui/Surface';

const BADGE_COLORS = {
  info: theme.info,
  warning: theme.warning,
  error: theme.danger,
  success: theme.success,
} as const;

export function AgentMessageRow({
  item,
  onToggleBatch,
}: {
  item: AgentChatItem;
  onToggleBatch: (id: string) => void;
}): React.JSX.Element {
  switch (item.kind) {
    case 'user':
      return (
        <View style={[styles.bubble, styles.user]}>
          <Mono>{item.text}</Mono>
        </View>
      );
    case 'assistant':
      return (
        <View style={[styles.bubble, styles.assistant]}>
          <Mono color={theme.textPrimary}>
            {item.text}
            {item.streaming ? ' ▋' : ''}
          </Mono>
        </View>
      );
    case 'toolBatch':
      return (
        <Pressable
          accessibilityRole="button"
          onPress={() => onToggleBatch(item.id)}
          style={styles.batch}
        >
          <Mono color={theme.textSecondary} size={12} weight="600">
            {item.collapsed ? '▸ ' : '▾ '}
            {batchSummary(item.tools)}
          </Mono>
          {!item.collapsed &&
            item.tools.map((t) => (
              <View key={t.id} style={styles.toolRow}>
                <Mono
                  color={toolFailed(t) ? theme.danger : theme.info}
                  size={12}
                  weight="600"
                >
                  {toolDisplayName(t.tool)}
                </Mono>
                <Mono color={theme.textSecondary} size={11} numberOfLines={1}>
                  {t.inputSummary}
                </Mono>
                {t.fileDiffs?.map((d) => (
                  <Mono key={d.path} color={theme.textTertiary} size={10}>
                    {`+${d.added} -${d.removed} ${baseName(d.path)}`}
                  </Mono>
                ))}
              </View>
            ))}
        </Pressable>
      );
    case 'permission':
      return (
        <View style={[styles.bubble, styles.permission]}>
          <Mono color={theme.warning} size={12} weight="700">
            Permission · {item.event.tool}
          </Mono>
          <Mono color={theme.textSecondary} size={12}>
            {item.event.inputSummary}
          </Mono>
        </View>
      );
    case 'statusBadge':
      return (
        <View style={styles.badgeRow}>
          <Mono color={BADGE_COLORS[item.badge]} size={11} weight="700">
            {item.text}
          </Mono>
        </View>
      );
    case 'turnSummary':
      return (
        <View style={styles.summary}>
          <Mono color={theme.textTertiary} size={11}>
            {[
              item.cost !== undefined ? `$${item.cost.toFixed(4)}` : null,
              item.inputTokens !== undefined ? `${item.inputTokens} in` : null,
              item.outputTokens !== undefined ? `${item.outputTokens} out` : null,
              item.effortLevel,
            ]
              .filter(Boolean)
              .join('  ·  ')}
          </Mono>
        </View>
      );
    /* istanbul ignore next -- exhaustive switch; sessionError is the final arm. */
    case 'sessionError':
      return (
        <View style={[styles.bubble, styles.error]}>
          <Mono color={theme.danger} size={12} weight="700">
            Stopped: {item.reason}
          </Mono>
        </View>
      );
  }
}

const styles = StyleSheet.create({
  bubble: {
    borderRadius: radius.md,
    padding: space.md,
    marginVertical: space.xs,
    maxWidth: '90%',
  },
  user: {
    alignSelf: 'flex-end',
    backgroundColor: theme.surfaceHi,
  },
  assistant: {
    alignSelf: 'flex-start',
    backgroundColor: theme.surface,
    borderWidth: 1,
    borderColor: theme.stroke,
  },
  batch: {
    alignSelf: 'flex-start',
    backgroundColor: theme.bgElevated,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: theme.stroke,
    padding: space.sm,
    marginVertical: space.xs,
    maxWidth: '95%',
    gap: space.xs,
  },
  toolRow: { gap: 2, paddingVertical: 2 },
  permission: {
    alignSelf: 'stretch',
    backgroundColor: 'rgba(250,204,21,0.08)',
    borderWidth: 1,
    borderColor: theme.warning,
    gap: space.xs,
  },
  badgeRow: { alignSelf: 'center', paddingVertical: space.xs },
  summary: { alignSelf: 'center', paddingVertical: space.xs },
  error: {
    alignSelf: 'stretch',
    backgroundColor: 'rgba(248,113,113,0.08)',
    borderWidth: 1,
    borderColor: theme.danger,
  },
});
