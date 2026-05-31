/**
 * Subscribe a component to an `Observable` view-model. Uses
 * `useSyncExternalStore` so React stays in sync with imperative store mutations
 * without prop-drilling. The selector derives the rendered slice.
 *
 * `getSnapshot` MUST return a referentially stable value between notifications,
 * or useSyncExternalStore loops forever. Selectors here often compute fresh
 * values (sorted/filtered arrays), so we memoise the derived result keyed on the
 * observable's monotonic `version`: the cached value is reused until the next
 * notify bumps the version.
 */

import { useCallback, useRef, useSyncExternalStore } from 'react';
import { Observable } from '@/lib/observable';

export function useObservable<O extends Observable, T>(
  observable: O,
  selector: (o: O) => T,
): T {
  const cache = useRef<{
    version: number;
    selector: (o: O) => T;
    value: T;
  } | null>(null);

  const subscribe = useCallback(
    (onChange: () => void) => observable.subscribe(onChange),
    [observable],
  );

  // Not memoised on `selector`: callers often pass an inline closure that
  // captures local state (e.g. a selected file). Recompute when either the
  // store version OR the selector identity changes; otherwise reuse the cached
  // reference so useSyncExternalStore sees a stable snapshot.
  const getSnapshot = (): T => {
    const version = observable.version;
    const cached = cache.current;
    if (cached !== null && cached.version === version && cached.selector === selector) {
      return cached.value;
    }
    const value = selector(observable);
    cache.current = { version, selector, value };
    return value;
  };

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
