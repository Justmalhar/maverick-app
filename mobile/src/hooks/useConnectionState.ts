/**
 * Subscribe to the MaverickClient connection state via its Emitter. Separate
 * from useObservable because the client exposes an Emitter (RN-1 core), not an
 * Observable view-model.
 */
import { useCallback, useSyncExternalStore } from 'react';
import { MaverickClient } from '@/app/maverick-client';
import { ConnectionState } from '@/net/connection-manager';

export function useConnectionState(client: MaverickClient): ConnectionState {
  const subscribe = useCallback(
    (onChange: () => void) => client.states.on(onChange),
    [client],
  );
  const getSnapshot = useCallback(() => client.state, [client]);
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
