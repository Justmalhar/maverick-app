import { render } from '@testing-library/react-native';
import { Text } from 'react-native';
import { AppProvider, useApp } from './AppProvider';
import { makeAppModel } from '@/test/render';

function Probe(): React.JSX.Element {
  const app = useApp();
  return <Text>{app.client.state}</Text>;
}

describe('AppProvider', () => {
  it('provides the injected model to descendants', () => {
    const model = makeAppModel();
    const { getByText } = render(
      <AppProvider model={model}>
        <Probe />
      </AppProvider>,
    );
    expect(getByText('connected')).toBeTruthy();
  });

  it('creates a default model when none is injected', () => {
    const { getByText } = render(
      <AppProvider>
        <Probe />
      </AppProvider>,
    );
    expect(getByText('disconnected')).toBeTruthy();
  });

  it('throws when useApp is used outside a provider', () => {
    const spy = jest.spyOn(console, 'error').mockImplementation(() => {});
    expect(() => render(<Probe />)).toThrow(/AppProvider/);
    spy.mockRestore();
  });
});
