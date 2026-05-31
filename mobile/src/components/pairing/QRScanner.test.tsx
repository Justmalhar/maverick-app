import { fireEvent } from '@testing-library/react-native';

let mockPermission: { granted: boolean; canAskAgain: boolean } | null = {
  granted: true,
  canAskAgain: true,
};
const mockRequestPermission = jest.fn(async () => {
  mockPermission = { granted: true, canAskAgain: true };
  return mockPermission;
});

jest.mock('expo-camera', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    useCameraPermissions: () => [mockPermission, mockRequestPermission],
    CameraView: (props: Record<string, unknown>) =>
      React.createElement(View, props),
  };
});

import { QRScanner } from './QRScanner';
import { render } from '@testing-library/react-native';

describe('QRScanner', () => {
  beforeEach(() => {
    mockPermission = { granted: true, canAskAgain: true };
    mockRequestPermission.mockClear();
  });

  it('scans a QR once and emits the data', () => {
    const onScan = jest.fn();
    const { getByTestId } = render(<QRScanner onScan={onScan} />);
    const cam = getByTestId('qr-camera');
    fireEvent(cam, 'barcodeScanned', { data: 'maverick://pair/v1?k=x&t=y' });
    fireEvent(cam, 'barcodeScanned', { data: 'second' });
    expect(onScan).toHaveBeenCalledTimes(1);
    expect(onScan).toHaveBeenCalledWith('maverick://pair/v1?k=x&t=y');
  });

  it('renders a loading state when permission is undetermined', () => {
    mockPermission = null;
    const { getByTestId } = render(<QRScanner onScan={jest.fn()} />);
    expect(getByTestId('qr-loading')).toBeTruthy();
  });

  it('renders a denied state and can re-request', () => {
    mockPermission = { granted: false, canAskAgain: true };
    const { getByTestId, getByText } = render(<QRScanner onScan={jest.fn()} />);
    expect(getByTestId('qr-denied')).toBeTruthy();
    fireEvent.press(getByText('Grant access'));
    expect(mockRequestPermission).toHaveBeenCalled();
  });

  it('re-arms the one-shot latch when resetKey changes (Try again)', () => {
    const onScan = jest.fn();
    const { getByTestId, rerender } = render(
      <QRScanner onScan={onScan} resetKey={0} />,
    );
    const cam = getByTestId('qr-camera');
    fireEvent(cam, 'barcodeScanned', { data: 'first' });
    // Latched: a second scan is ignored until reset.
    fireEvent(cam, 'barcodeScanned', { data: 'ignored' });
    expect(onScan).toHaveBeenCalledTimes(1);

    // "Try again" bumps resetKey → the latch clears → a new scan fires again.
    rerender(<QRScanner onScan={onScan} resetKey={1} />);
    fireEvent(getByTestId('qr-camera'), 'barcodeScanned', { data: 'second' });
    expect(onScan).toHaveBeenCalledTimes(2);
    expect(onScan).toHaveBeenLastCalledWith('second');
  });
});
