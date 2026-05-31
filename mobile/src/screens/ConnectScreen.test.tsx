const mockPush = jest.fn();
jest.mock('expo-router', () => ({
  useRouter: () => ({ push: mockPush, replace: jest.fn() }),
}));

import { fireEvent } from '@testing-library/react-native';
import { ConnectScreen } from './ConnectScreen';
import { makeAppModel, renderWithApp } from '@/test/render';

describe('ConnectScreen', () => {
  beforeEach(() => mockPush.mockClear());

  it('connects with a valid manual target and routes to sessions', () => {
    const app = makeAppModel();
    const { getByLabelText, getByText } = renderWithApp(<ConnectScreen />, app);
    fireEvent.changeText(getByLabelText('Mac Address'), 'mac.ts.net');
    fireEvent.changeText(getByLabelText('Port'), '8765');
    fireEvent.press(getByText('Connect'));
    expect(mockPush).toHaveBeenCalledWith('/sessions');
    expect(app.history.hosts).toHaveLength(1);
  });

  it('shows a validation error for an empty host', () => {
    const app = makeAppModel();
    const { getByText } = renderWithApp(<ConnectScreen />, app);
    fireEvent.press(getByText('Connect'));
    expect(getByText(/address/)).toBeTruthy();
    expect(mockPush).not.toHaveBeenCalled();
  });

  it('prefills from a saved server and offers the QR entry point', () => {
    const app = makeAppModel();
    app.history.record('saved.ts.net', 9001, { name: 'Studio', token: 't' });
    const { getByText } = renderWithApp(<ConnectScreen />, app);
    fireEvent.press(getByText('Studio'));
    fireEvent.press(getByText('Scan QR to pair'));
    expect(mockPush).toHaveBeenCalledWith('/pair');
  });
});
