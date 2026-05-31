const mockReplace = jest.fn();
jest.mock('expo-router', () => ({
  useRouter: () => ({ replace: mockReplace }),
}));

let mockPermission: { granted: boolean; canAskAgain: boolean } | null = {
  granted: true,
  canAskAgain: true,
};
jest.mock('expo-camera', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    useCameraPermissions: () => [mockPermission, jest.fn()],
    CameraView: (props: Record<string, unknown>) => React.createElement(View, props),
  };
});

import { render } from '@testing-library/react-native';
import { AppProvider } from '@/components/AppProvider';
import { PairScreen } from './PairScreen';
import { makeAppModel } from '@/test/render';

describe('PairScreen', () => {
  beforeEach(() => {
    mockReplace.mockClear();
    mockPermission = { granted: true, canAskAgain: true };
  });

  it('mounts the scanner in the idle stage', () => {
    const model = makeAppModel();
    const { getByTestId } = render(
      <AppProvider model={model}>
        <PairScreen />
      </AppProvider>,
    );
    expect(getByTestId('qr-camera')).toBeTruthy();
  });
});
