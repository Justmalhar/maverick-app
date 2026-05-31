/**
 * QR pairing screen. Scans a maverick:// QR, runs the Noise_XX handshake over a
 * LAN pairing channel, shows the TOFU safety-number for out-of-band
 * verification, and persists the paired device on confirm.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
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
import {
  parsePairingPayload,
  rendezvousTarget,
  type RendezvousTarget,
} from '@/pairing/qr-payload';
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
  const lastScan = useRef<RendezvousTarget | null>(null);
  const [scanGeneration, setScanGeneration] = useState(0);

  const retry = useCallback(() => {
    lastScan.current = null;
    setScanGeneration((g) => g + 1);
    controller.reset();
  }, [controller]);

  const onScan = useCallback(
    (data: string) => {
      // Derive the real rendezvous host/port from the scanned QR's relay hint
      // (falling back to the LAN default) so the paired device records an
      // address it can actually reconnect to.
      let target: RendezvousTarget;
      try {
        target = rendezvousTarget(parsePairingPayload(data));
      } catch {
        // Let the controller surface the parse error; dial the LAN default so
        // the (doomed) handshake fails cleanly rather than throwing here.
        target = { host: 'pair.local', port: 8765 };
      }
      lastScan.current = target;
      /* istanbul ignore next -- exercising the real LAN socket requires a
         device; covered by PairingController tests with a fake channel. */
      void controller.pair(
        data,
        new LanPairingChannel(lanPairingUrl(target.host, target.port)),
      );
    },
    [controller],
  );

  const confirm = useCallback(() => {
    const t = lastScan.current;
    /* istanbul ignore else -- confirm is only reachable after a scan set this. */
    if (t !== null) controller.confirm(t.host, t.port);
    // Navigation happens from the stage==='paired' effect, only after the
    // controller actually persists the device; a failed confirm() drops to
    // the 'error' stage and keeps the user on this screen.
  }, [controller]);

  useEffect(() => {
    if (stage === 'paired') router.replace('/');
  }, [stage, router]);

  return (
    <View style={styles.root}>
      {(stage === 'idle' || stage === 'parsing' || stage === 'handshaking') && (
        <QRScanner onScan={onScan} resetKey={scanGeneration} />
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
            onPress={retry}
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
