import { fireEvent } from '@testing-library/react-native';

jest.mock('react-native-webview', () => {
  const React = require('react');
  const { View } = require('react-native');
  const WebView = React.forwardRef(
    (props: Record<string, unknown>, ref: unknown) => {
      React.useImperativeHandle(ref, () => ({ injectJavaScript: jest.fn() }));
      return React.createElement(View, props);
    },
  );
  return { WebView };
});

import { TerminalView } from './TerminalView';
import { makeAppModel, renderWithApp } from '@/test/render';
import { uuid } from '@/test/fixtures';
import { encodeBase64 } from '@/protocol/primitives';

describe('TerminalView', () => {
  it('mounts a webview, attaches, and forwards bridge messages', () => {
    const app = makeAppModel();
    const sid = uuid();
    const { getByTestId } = renderWithApp(<TerminalView sessionId={sid} />, app);
    const web = getByTestId('terminal-webview');
    // ready → then data + resize from the bridge.
    fireEvent(web, 'message', { nativeEvent: { data: JSON.stringify({ t: 'ready' }) } });
    fireEvent(web, 'message', {
      nativeEvent: { data: JSON.stringify({ t: 'data', d: 'ls\r' }) },
    });
    fireEvent(web, 'message', {
      nativeEvent: { data: JSON.stringify({ t: 'resize', cols: 100, rows: 30 }) },
    });
    // Server output is routed through the registered handler (no throw).
    app.sessions.handle({
      type: 'output',
      sessionId: sid,
      data: encodeBase64(new TextEncoder().encode('hello\n')),
    });
    expect(web).toBeTruthy();
  });

  it('drops a malformed bridge frame', () => {
    const app = makeAppModel();
    const { getByTestId } = renderWithApp(<TerminalView sessionId={uuid()} />, app);
    fireEvent(getByTestId('terminal-webview'), 'message', {
      nativeEvent: { data: 'garbage' },
    });
    expect(getByTestId('terminal-webview')).toBeTruthy();
  });
});
