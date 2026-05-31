/**
 * Hosts xterm.js inside a react-native-webview. Server terminal frames
 * (output/scrollback) are decoded by a TerminalBuffer and pushed into the
 * webview via injected JS; user keystrokes + resize come back over the bridge
 * and are forwarded to the session (input / resize). OSC-7 cwd is surfaced to
 * the session store so the Files/Diff tabs re-root.
 */
import { useCallback, useEffect, useMemo, useRef } from 'react';
import { StyleSheet, View } from 'react-native';
import { WebView, WebViewMessageEvent } from 'react-native-webview';
import { useApp } from '../AppProvider';
import { TerminalBuffer } from '@/terminal/terminal-buffer';
import {
  parseWebViewMessage,
  terminalHtml,
  writeScript,
} from '@/terminal/webview-bridge';
import { InputToolbar } from './InputToolbar';
import { theme } from '../theme';

export function TerminalView({ sessionId }: { sessionId: string }): React.JSX.Element {
  const app = useApp();
  const webRef = useRef<WebView>(null);
  const buffer = useMemo(() => new TerminalBuffer(), []);
  const ready = useRef(false);

  useEffect(() => {
    app.client.attach(sessionId);
    app.sessions.registerOutputHandler(sessionId, (b64) => {
      const chunk = buffer.ingest(b64);
      if (chunk.cwd !== undefined) app.sessions.updateCwd(sessionId, chunk.cwd);
      /* istanbul ignore else -- before `ready` the data is held in the buffer
         and replayed as the seed on the webview's ready message. */
      if (ready.current) webRef.current?.injectJavaScript(writeScript(chunk.text));
    });
    return () => app.sessions.unregisterOutputHandler(sessionId);
  }, [app, buffer, sessionId]);

  const onMessage = useCallback(
    (e: WebViewMessageEvent) => {
      const msg = parseWebViewMessage(e.nativeEvent.data);
      /* istanbul ignore if -- defensive: malformed bridge frames are dropped. */
      if (msg === null) return;
      if (msg.t === 'ready') {
        ready.current = true;
      } else if (msg.t === 'data') {
        app.client.input(sessionId, msg.d);
      } else {
        app.client.resize(sessionId, msg.cols, msg.rows);
      }
    },
    [app, sessionId],
  );

  return (
    <View style={styles.root}>
      <WebView
        ref={webRef}
        originWhitelist={['*']}
        source={{ html: terminalHtml(buffer.snapshot()) }}
        onMessage={onMessage}
        style={styles.web}
        testID="terminal-webview"
      />
      <InputToolbar sessionId={sessionId} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  web: { flex: 1, backgroundColor: theme.bg },
});
