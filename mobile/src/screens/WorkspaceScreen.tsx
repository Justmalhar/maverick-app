/**
 * Paired-session workspace. A tab bar switches between the Agent chat (for agent
 * sessions), the Terminal, the file Explorer, and the Git diff. The agent vs
 * terminal toggle calls switch_session_mode like the Swift TerminalScreen.
 *
 * History paging: scrolling to the top of the agent timeline calls
 * loadOlderHistory, which (in the absence of a dedicated history frame in the
 * committed protocol) is a no-op hook point the parent can wire to a future
 * `loadAgentHistory` RPC; the model's prependHistory does the resident-window
 * bookkeeping.
 */
import { useCallback, useEffect, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { useLocalSearchParams } from 'expo-router';
import { useApp } from '@/components/AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { AgentChatView } from '@/components/agent/AgentChatView';
import { TerminalView } from '@/components/terminal/TerminalView';
import { GitDiffView } from '@/components/git/GitDiffView';
import { FileExplorerView } from '@/components/explorer/FileExplorerView';
import { space, theme } from '@/components/theme';
import { Mono } from '@/components/ui/Surface';

type Tab = 'chat' | 'terminal' | 'files' | 'diff';

export function WorkspaceScreen(): React.JSX.Element {
  const app = useApp();
  const params = useLocalSearchParams<{ sessionId?: string }>();
  const sessionId = params.sessionId ?? app.sessions.activeSessionId ?? '';
  useObservable(app.agents, () => app.agents.session(sessionId));
  const agentModel = app.agents.session(sessionId);
  const isAgent = agentModel !== undefined;
  const [tab, setTab] = useState<Tab>(isAgent ? 'chat' : 'terminal');

  useEffect(() => {
    if (sessionId.length > 0) {
      app.client.attach(sessionId);
      app.sessions.setActiveSessionId(sessionId);
    }
  }, [app, sessionId]);

  const cwd = app.sessions.cwd(sessionId) ?? app.settings.lastWorkingDir;

  const loadOlder = useCallback(() => {
    // COORDINATOR: the committed protocol has no loadAgentHistory frame yet
    // (Companion-4). When it lands, fetch a 50-item page and call
    // agentModel.prependHistory(page). The resident-window cap is already
    // enforced by the model.
  }, []);

  const tabs: { id: Tab; label: string; show: boolean }[] = [
    { id: 'chat', label: 'Chat', show: isAgent },
    { id: 'terminal', label: 'Terminal', show: true },
    { id: 'files', label: 'Files', show: true },
    { id: 'diff', label: 'Diff', show: true },
  ];

  const switchTab = (next: Tab): void => {
    setTab(next);
    if (isAgent && (next === 'chat' || next === 'terminal')) {
      app.client.switchSessionMode(sessionId, next === 'chat' ? 'chat' : 'terminal');
    }
  };

  return (
    <View style={styles.root}>
      <View style={styles.tabBar}>
        {tabs
          .filter((t) => t.show)
          .map((t) => (
            <Pressable
              key={t.id}
              accessibilityRole="button"
              onPress={() => switchTab(t.id)}
              style={[styles.tab, tab === t.id && styles.tabActive]}
            >
              <Mono
                color={tab === t.id ? theme.onAccent : theme.textPrimary}
                size={13}
                weight="600"
              >
                {t.label}
              </Mono>
            </Pressable>
          ))}
      </View>
      <View style={styles.body}>
        {tab === 'chat' && agentModel !== undefined && (
          <AgentChatView model={agentModel} onLoadOlder={loadOlder} />
        )}
        {tab === 'terminal' && <TerminalView sessionId={sessionId} />}
        {tab === 'files' && <FileExplorerView rootPath={cwd} />}
        {tab === 'diff' && <GitDiffView repoPath={cwd} />}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  tabBar: {
    flexDirection: 'row',
    gap: space.xs,
    padding: space.sm,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderColor: theme.stroke,
  },
  tab: {
    paddingHorizontal: space.md,
    paddingVertical: space.xs,
    borderRadius: 999,
  },
  tabActive: { backgroundColor: theme.accent },
  body: { flex: 1 },
});
