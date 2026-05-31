/**
 * QR scan surface using expo-camera barcode scanning. Emits the raw scanned
 * string (a `maverick://pair/...` URI) once; the parent runs it through the
 * PairingController. Requests camera permission on mount and renders a prompt
 * if denied.
 */
import { useEffect, useRef } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import {
  CameraView,
  useCameraPermissions,
  type BarcodeScanningResult,
} from 'expo-camera';
import { space, theme } from '../theme';
import { Mono } from '../ui/Surface';

export function QRScanner({
  onScan,
}: {
  onScan: (data: string) => void;
}): React.JSX.Element {
  const [permission, requestPermission] = useCameraPermissions();
  const handled = useRef(false);

  useEffect(() => {
    if (permission !== null && !permission.granted && permission.canAskAgain) {
      void requestPermission();
    }
  }, [permission, requestPermission]);

  const onResult = (result: BarcodeScanningResult): void => {
    if (handled.current) return;
    handled.current = true;
    onScan(result.data);
  };

  if (permission === null) {
    return (
      <View style={styles.center} testID="qr-loading">
        <Mono color={theme.textSecondary}>Preparing camera…</Mono>
      </View>
    );
  }

  if (!permission.granted) {
    return (
      <View style={styles.center} testID="qr-denied">
        <Mono color={theme.textSecondary}>Camera access is needed to scan.</Mono>
        <Pressable
          accessibilityRole="button"
          onPress={() => void requestPermission()}
          style={styles.btn}
        >
          <Mono color={theme.onAccent} weight="700">
            Grant access
          </Mono>
        </Pressable>
      </View>
    );
  }

  return (
    <CameraView
      style={styles.camera}
      facing="back"
      barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
      onBarcodeScanned={onResult}
      testID="qr-camera"
    />
  );
}

const styles = StyleSheet.create({
  camera: { flex: 1 },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: space.md,
    backgroundColor: theme.bg,
  },
  btn: {
    backgroundColor: theme.accent,
    paddingHorizontal: space.lg,
    paddingVertical: space.sm,
    borderRadius: 999,
  },
});
