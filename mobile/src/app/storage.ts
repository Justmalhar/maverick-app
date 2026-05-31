/**
 * Synchronous key/value persistence abstraction. The Swift client uses
 * `UserDefaults` (synchronous). RN's persistent stores (expo-secure-store,
 * AsyncStorage) are async, so we model the contract as a synchronous in-memory
 * cache that is *hydrated* and *flushed* by an async backend. View-models read
 * and write synchronously against the cache; the backend persists in the
 * background. This keeps every view-model unit-testable with the in-memory
 * default and free of any RN/Expo import.
 */

export interface KeyValueStore {
  getString(key: string): string | undefined;
  setString(key: string, value: string): void;
  remove(key: string): void;
}

/** In-memory store — the default, and the one used in every unit test. */
export class MemoryStore implements KeyValueStore {
  private readonly map = new Map<string, string>();

  getString(key: string): string | undefined {
    return this.map.get(key);
  }

  setString(key: string, value: string): void {
    this.map.set(key, value);
  }

  remove(key: string): void {
    this.map.delete(key);
  }

  /** Snapshot of all entries — used by an async backend to flush. */
  entries(): [string, string][] {
    return [...this.map.entries()];
  }
}
