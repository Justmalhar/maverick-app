/**
 * Tiny observable base for view-models. Swift's `@Observable` re-renders any
 * SwiftUI view that reads a changed property; React has no such mechanism, so
 * each view-model extends `Observable` and calls `notify()` after a mutation.
 * Thin RN components subscribe with the `useObservable` hook (see hooks/).
 *
 * Kept independent of React so the logic layer stays unit-testable without a
 * renderer, mirroring the RN-1 core's environment-independence rule.
 */

export type Unsubscribe = () => void;

export class Observable {
  private readonly listeners = new Set<() => void>();
  private revision = 0;

  subscribe(listener: () => void): Unsubscribe {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  /**
   * Monotonic change counter. `useObservable` reads this to memoise a derived
   * snapshot so selectors that compute fresh values (sorted arrays, filtered
   * lists) don't trigger an infinite render loop under useSyncExternalStore.
   */
  get version(): number {
    return this.revision;
  }

  protected notify(): void {
    this.revision += 1;
    // Snapshot so a listener that unsubscribes mid-emit can't skip another.
    for (const listener of [...this.listeners]) listener();
  }

  get listenerCount(): number {
    return this.listeners.size;
  }
}
