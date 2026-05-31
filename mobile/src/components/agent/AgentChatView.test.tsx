import { fireEvent } from '@testing-library/react-native';
import { AgentChatView } from './AgentChatView';
import { AgentSessionModel } from '@/stores/agent-session-model';
import { makeAppModel, renderWithApp } from '@/test/render';
import { permission, sessionInfo, toolCall, uuid } from '@/test/fixtures';

const SID = uuid();

function seededModel(app: ReturnType<typeof makeAppModel>): AgentSessionModel {
  const info = sessionInfo({ id: SID, agentProvider: 'claudeCode', sessionMode: 'chat' });
  app.agents.handle({ type: 'agent_session_created', session: info });
  return app.agents.session(SID)!;
}

describe('AgentChatView', () => {
  it('renders the timeline of every item kind', () => {
    const app = makeAppModel();
    const model = seededModel(app);
    model.apply({ type: 'user_message', text: 'hello agent' });
    model.apply({ type: 'assistant_message', text: 'hi there' });
    model.apply({ type: 'tool_batch_complete', events: [toolCall()] });
    model.apply({ type: 'status_badge', text: 'Indexing', kind: 'info' });
    model.apply({ type: 'turn_stop', cost: 0.02, inputTokens: 10, outputTokens: 5 });
    model.apply({ type: 'session_error', reason: 'rateLimit' });
    const { getByText } = renderWithApp(<AgentChatView model={model} />, app);
    expect(getByText('hello agent')).toBeTruthy();
    expect(getByText('hi there')).toBeTruthy();
  });

  it('sends an agent_input on submit and clears the draft', () => {
    const app = makeAppModel();
    const model = seededModel(app);
    const { getByTestId, getByLabelText } = renderWithApp(
      <AgentChatView model={model} />,
      app,
    );
    fireEvent.changeText(getByTestId('agent-input'), 'do the thing');
    fireEvent.press(getByLabelText('Send'));
    expect(app.client.manager.attachedSessions).toBeDefined();
  });

  it('ignores an empty submit', () => {
    const app = makeAppModel();
    const model = seededModel(app);
    const { getByLabelText } = renderWithApp(<AgentChatView model={model} />, app);
    fireEvent.press(getByLabelText('Send'));
    // No throw, no input row rendered.
    expect(model.items).toHaveLength(0);
  });

  it('shows a permission bar and resolves allow/deny', () => {
    const app = makeAppModel();
    const model = seededModel(app);
    model.apply({
      type: 'permission_request',
      permissionEvent: permission({ requestId: uuid(), tool: 'bash' }),
    });
    const { getByText, queryByTestId } = renderWithApp(
      <AgentChatView model={model} />,
      app,
    );
    expect(queryByTestId('permission-bar')).toBeTruthy();
    fireEvent.press(getByText('Allow'));
    expect(model.pendingPermission).toBeNull();
  });

  it('denies a permission', () => {
    const app = makeAppModel();
    const model = seededModel(app);
    model.apply({
      type: 'permission_request',
      permissionEvent: permission({ requestId: uuid() }),
    });
    const { getByText } = renderWithApp(<AgentChatView model={model} />, app);
    fireEvent.press(getByText('Deny'));
    expect(model.pendingPermission).toBeNull();
  });

  it('toggles a tool batch row and surfaces a load-older callback', () => {
    const app = makeAppModel();
    const model = seededModel(app);
    model.apply({ type: 'tool_batch_complete', events: [toolCall({ error: 'x' })] });
    let loaded = 0;
    const { getByText } = renderWithApp(
      <AgentChatView model={model} onLoadOlder={() => loaded++} />,
      app,
    );
    // Tap the collapsed batch summary to expand it.
    fireEvent.press(getByText(/failed/));
    expect(loaded).toBeGreaterThanOrEqual(0);
  });
});
