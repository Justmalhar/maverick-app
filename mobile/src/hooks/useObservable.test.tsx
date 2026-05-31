import { act, render } from '@testing-library/react-native';
import { Text } from 'react-native';
import { useObservable } from './useObservable';
import { useConnectionState } from './useConnectionState';
import { Observable } from '@/lib/observable';
import { makeAppModel } from '@/test/render';

class Counter extends Observable {
  value = 0;
  inc(): void {
    this.value++;
    this.notify();
  }
}

function CounterView({ counter }: { counter: Counter }): React.JSX.Element {
  const v = useObservable(counter, (c) => c.value);
  return <Text>count:{v}</Text>;
}

describe('useObservable', () => {
  it('re-renders when the observable notifies', () => {
    const counter = new Counter();
    const { getByText } = render(<CounterView counter={counter} />);
    expect(getByText('count:0')).toBeTruthy();
    act(() => counter.inc());
    expect(getByText('count:1')).toBeTruthy();
  });
});

function ConnView(): React.JSX.Element {
  const app = makeAppModel();
  const state = useConnectionState(app.client);
  return <Text>{state}</Text>;
}

describe('useConnectionState', () => {
  it('reflects the current connection state', () => {
    const { getByText } = render(<ConnView />);
    expect(getByText('connected')).toBeTruthy();
  });
});
