/**
 * Connect screen: hero, saved-servers list (tap to prefill), manual host/port/
 * token entry, and a "Scan QR" entry point. Connecting records the host in
 * history and dials the client; navigation to the workspace is driven by the
 * router when the connection state flips to connected.
 */
import { useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  TextInput,
  View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useApp } from '@/components/AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { parseManualTarget } from '@/app/connect-input';
import { hostDisplayName } from '@/app/connection-history';
import { radius, space, theme } from '@/components/theme';
import { Card, Mono } from '@/components/ui/Surface';

export function ConnectScreen(): React.JSX.Element {
  const app = useApp();
  const router = useRouter();
  const hosts = useObservable(app.history, (h) => h.sortedByRecency);
  const [host, setHost] = useState('');
  const [port, setPort] = useState('8765');
  const [token, setToken] = useState('');
  const [error, setError] = useState<string | null>(null);

  const connect = (): void => {
    const parsed = parseManualTarget(host, port, token);
    if (!parsed.ok || parsed.target === undefined) {
      setError(parsed.error ?? 'Invalid target');
      return;
    }
    setError(null);
    const opts: { token?: string } = {};
    if (parsed.target.token !== undefined) opts.token = parsed.target.token;
    app.history.record(parsed.target.host, parsed.target.port, opts);
    app.client.connect(parsed.target);
    router.push('/sessions');
  };

  return (
    <ScrollView style={styles.root} contentContainerStyle={styles.content}>
      <View style={styles.hero}>
        <Mono size={32} weight="700">
          Maverick
        </Mono>
        <Mono color={theme.textSecondary} size={13}>
          Your Mac’s terminal, in your pocket.
        </Mono>
      </View>

      {hosts.length > 0 && (
        <View style={styles.section}>
          <Mono color={theme.textSecondary} size={12} weight="600">
            Saved Servers
          </Mono>
          {hosts.map((h) => (
            <Pressable
              key={h.id}
              accessibilityRole="button"
              onPress={() => {
                setHost(h.host);
                setPort(String(h.port));
                if (h.token !== undefined) setToken(h.token);
              }}
              style={styles.savedRow}
            >
              <Mono weight="600">{hostDisplayName(h)}</Mono>
              <Mono color={theme.textSecondary} size={11}>
                {h.host}:{h.port}
              </Mono>
            </Pressable>
          ))}
        </View>
      )}

      <Card style={styles.form}>
        <Field label="Mac Address" value={host} onChange={setHost} placeholder="100.x.x.x" />
        <Field label="Port" value={port} onChange={setPort} placeholder="8765" keyboard="number-pad" />
        <Field label="Token (optional)" value={token} onChange={setToken} placeholder="shared secret" secure />
      </Card>

      <Pressable accessibilityRole="button" onPress={connect} style={styles.connect}>
        <Mono color={theme.onAccent} weight="700">
          Connect
        </Mono>
      </Pressable>

      <Pressable
        accessibilityRole="button"
        onPress={() => router.push('/pair')}
        style={styles.scan}
      >
        <Mono color={theme.accent} weight="600">
          Scan QR to pair
        </Mono>
      </Pressable>

      {error !== null && (
        <Mono color={theme.danger} size={12} style={styles.error}>
          {error}
        </Mono>
      )}
    </ScrollView>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  keyboard = 'default',
  secure = false,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  keyboard?: 'default' | 'number-pad';
  secure?: boolean;
}): React.JSX.Element {
  return (
    <View style={styles.field}>
      <Mono color={theme.textSecondary} size={12} weight="600">
        {label}
      </Mono>
      <TextInput
        style={styles.input}
        value={value}
        onChangeText={onChange}
        placeholder={placeholder}
        placeholderTextColor={theme.textTertiary}
        keyboardType={keyboard}
        secureTextEntry={secure}
        autoCapitalize="none"
        autoCorrect={false}
        accessibilityLabel={label}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  content: { padding: space.xl, gap: space.lg },
  hero: { alignItems: 'center', gap: space.sm, paddingTop: space.xl },
  section: { gap: space.sm },
  savedRow: {
    backgroundColor: theme.surface,
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: theme.stroke,
    padding: space.md,
    gap: 2,
  },
  form: { gap: space.md },
  field: { gap: space.xs },
  input: {
    color: theme.textPrimary,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: radius.md,
    borderWidth: 1,
    borderColor: theme.stroke,
    paddingHorizontal: space.md,
    paddingVertical: space.sm,
  },
  connect: {
    backgroundColor: theme.accent,
    borderRadius: radius.pill,
    paddingVertical: space.md,
    alignItems: 'center',
  },
  scan: { alignItems: 'center', paddingVertical: space.sm },
  error: { textAlign: 'center' },
});
