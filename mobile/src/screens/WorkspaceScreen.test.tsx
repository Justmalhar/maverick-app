let mockParams: { sessionId?: string } = {};
jest.mock('expo-router', () => ({
  useLocalSearchParams: () => mockParams,
}));
jest.mock('react-native-webview', () => {
  const React = require('react');
  const { View } = require('react-native');
  const WebView = React.forwardRef((props: Record<string, unknown>, ref: unknown) => {
    React.useImperativeHandle(ref, () => ({ injectJavaScript: jest.fn() }));
    return React.createElement(View, props);
  });
  return { WebView };
});

import { fireEvent } from '@testing-library/react-native';
import { WorkspaceScreen } from './WorkspaceScreen';
import { makeAppModel, renderWithApp } from '@/test/render';
import { sessionInfo, uuid } from '@/test/fixtures';

describe('WorkspaceScreen', () => {
  it('renders agent chat tab for an agent session and switches modes', () => {
    const app = makeAppModel();
    const sid = uuid();
    app.agents.handle({
      type: 'agent_session_created',
      session: sessionInfo({ id: sid, agentProvider: 'claudeCode', sessionMode: 'chat' }),
    });
    mockParams = { sessionId: sid };
    const { getByText, getByTestId } = renderWithApp(<WorkspaceScreen />, app);
    expect(getByTestId('agent-timeline')).toBeTruthy();
    // Switch to Terminal → switch_session_mode is issued.
    fireEvent.press(getByText('Terminal'));
    expect(getByTestId('terminal-webview')).toBeTruthy();
    // Files + Diff tabs.
    fireEvent.press(getByText('Files'));
    fireEvent.press(getByText('Diff'));
    // Back to chat.
    fireEvent.press(getByText('Chat'));
    expect(getByTestId('agent-timeline')).toBeTruthy();
  });

  it('renders a terminal-only workspace for a non-agent session', () => {
    const app = makeAppModel();
    const sid = uuid();
    mockParams = { sessionId: sid };
    const { getByTestId, queryByText } = renderWithApp(<WorkspaceScreen />, app);
    expect(getByTestId('terminal-webview')).toBeTruthy();
    expect(queryByText('Chat')).toBeNull();
  });
});
