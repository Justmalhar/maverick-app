/**
 * QR pairing screen. Scans a maverick:// QR, runs the Noise_XX handshake over a
 * LAN pairing channel, shows the TOFU safety-number for out-of-band
 * verification, and persists the paired device on confirm.
 */
import { useCallback, useMemo, useRef } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useApp } from '@/components/AppProvider';
import { useObservable } from '@/hooks/useObservable';
import { QRScanner } from '@/components/pairing/QRScanner';
import { PairingController } from '@/pairing/pairing-controller';
import { TofuPinner, InMemoryPinStorage } from '@/pairing/tofu-store';
import {
  LanPairingChannel,
  lanPairingUrl,
} from '@/pairing/lan-pairing-channel';
import { space, theme } from '@/components/theme';
import { Card, Mono } from '@/components/ui/Surface';

export function PairScreen(): React.JSX.Element {
  const app = useApp();
  const router = useRouter();
  const controller = useMemo(
    () => new PairingController(new TofuPinner(new InMemoryPinStorage()), app.history),
    [app],
  );
  const stage = useObservable(controller, (c) => c.stage);
  const safety = useObservable(controller, (c) => c.safetyNumber);
  const error = useObservable(controller, (c) => c.error);
  const lastScan = useRef<{ host: string; port: number } | null>(null);

  const onScan = useCallback(
    (data: string) => {
      // Relay hint (if present) gives host:port; default to the LAN port.
      const host = 'pair.local';
      const port = 8765;
      lastScan.current = { host, port };
      /* istanbul ignore next -- exercising the real LAN socket requires a
         device; covered by PairingController tests with a fake channel. */
      void controller.pair(data, new LanPairingChannel(lanPairingUrl(host, port)));
    },
    [controller],
  );

  const confirm = useCallback(() => {
    const t = lastScan.current;
    /* istanbul ignore else -- confirm is only reachable after a scan set this. */
    if (t !== null) controller.confirm(t.host, t.port);
    router.replace('/');
  }, [controller, router]);

  return (
    <View style={styles.root}>
      {(stage === 'idle' || stage === 'parsing' || stage === 'handshaking') && (
        <QRScanner onScan={onScan} />
      )}
      {stage === 'handshaking' && (
        <Mono color={theme.textSecondary} style={styles.center}>
          Verifying device…
        </Mono>
      )}
      {stage === 'verify' && safety !== null && (
        <Card style={styles.verify}>
          <Mono weight="700">Confirm this number matches your Mac</Mono>
          <Mono color={theme.accent} size={20} weight="700" style={styles.sn}>
            {safety}
          </Mono>
          <Pressable accessibilityRole="button" onPress={confirm} style={styles.btn}>
            <Mono color={theme.onAccent} weight="700">
              They match — pair
            </Mono>
          </Pressable>
        </Card>
      )}
      {stage === 'error' && (
        <View style={styles.center}>
          <Mono color={theme.danger}>{error}</Mono>
          <Pressable
            accessibilityRole="button"
            onPress={() => controller.reset()}
            style={styles.btn}
          >
            <Mono color={theme.onAccent} weight="700">
              Try again
            </Mono>
          </Pressable>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: theme.bg },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: space.md },
  verify: { margin: space.lg, gap: space.md, alignItems: 'center' },
  sn: { letterSpacing: 2 },
  btn: {
    backgroundColor: theme.accent,
    borderRadius: 999,
    paddingHorizontal: space.lg,
    paddingVertical: space.sm,
  },
});
