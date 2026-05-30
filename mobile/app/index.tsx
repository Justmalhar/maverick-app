import { useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { ConnectionManager } from '@/net/connection-manager';
import { LanTransport } from '@/net/transports';

/**
 * Placeholder home screen. The real connection / session UI lands in RN-2.
 * For now this proves the logic core (protocol + net + pairing) wires up
 * cleanly against the Expo runtime without pulling in any UI dependency the
 * core itself does not need.
 */
export default function Home() {
  const manager = useMemo(
    () => new ConnectionManager({ transportFactory: (url) => new LanTransport(url) }),
    [],
  );

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Maverick</Text>
      <Text style={styles.subtitle}>laptop = server, anything = client</Text>
      <Text style={styles.state}>connection: {manager.state}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  title: { color: '#f5f5f5', fontSize: 28, fontWeight: '700' },
  subtitle: { color: '#9b8cff', fontSize: 14 },
  state: { color: '#7a7a7a', fontSize: 12, marginTop: 16 },
});
