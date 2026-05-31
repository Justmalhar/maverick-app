const mockPush = jest.fn();
jest.mock('expo-router', () => ({
  useRouter: () => ({ push: mockPush }),
}));

import { act, fireEvent } from '@testing-library/react-native';
import { SessionsScreen } from './SessionsScreen';
import { makeAppModel, renderWithApp } from '@/test/render';
import { sessionInfo } from '@/test/fixtures';

describe('SessionsScreen', () => {
  beforeEach(() => mockPush.mockClear());

  it('lists agent + terminal sessions and resumes/attaches', () => {
    const app = makeAppModel();
    const agent = sessionInfo({ name: 'claude', agentProvider: 'claudeCode' });
    const term = sessionInfo({ name: 'build' });
    const { getByText, getAllByText } = renderWithApp(<SessionsScreen />, app);
    act(() => {
      app.sessions.handle({ type: 'session_list', sessions: [agent, term] });
    });
    expect(getByText('claude')).toBeTruthy();
    expect(getByText('build')).toBeTruthy();
    // Resume the agent.
    fireEvent.press(getAllByText('Resume')[0]!);
    expect(mockPush).toHaveBeenCalledWith(`/workspace?sessionId=${agent.id}`);
    // Attach the terminal.
    fireEvent.press(getAllByText('Attach')[0]!);
    expect(mockPush).toHaveBeenCalledWith(`/workspace?sessionId=${term.id}`);
  });

  it('shows an empty state', () => {
    const app = makeAppModel();
    const { getByText } = renderWithApp(<SessionsScreen />, app);
    expect(getByText('No sessions yet.')).toBeTruthy();
  });
});
