/**
 * Port of the Swift `ConnectionHistory` + `SavedHost`. Persists the list of
 * paired/known servers and bumps recency on each connect. Backed by a
 * `KeyValueStore` (JSON-encoded under one key) so it is fully synchronous and
 * testable.
 */

import { randomUUID } from '@/protocol/primitives';
import { KeyValueStore } from './storage';
import { Observable } from '@/lib/observable';

export interface SavedHost {
  id: string;
  name: string;
  host: string;
  port: number;
  /** Epoch millis of the last successful connect. */
  lastConnected: number;
  token?: string;
  /** base64url of the TOFU-pinned desktop static key (set after pairing). */
  pinnedKey?: string;
}

/** User-facing label — name if set, otherwise host:port. */
export function hostDisplayName(h: SavedHost): string {
  return h.name.length > 0 ? h.name : `${h.host}:${h.port}`;
}

const STORAGE_KEY = 'savedHosts.v2';

interface RecordOptions {
  name?: string;
  token?: string;
  pinnedKey?: string;
}

export class ConnectionHistory extends Observable {
  private hostsList: SavedHost[] = [];

  constructor(
    private readonly store: KeyValueStore,
    private readonly now: () => number = () => Date.now(),
  ) {
    super();
    this.load();
  }

  get hosts(): SavedHost[] {
    return this.hostsList;
  }

  /** Most-recently-connected first — the order the Connect screen renders. */
  get sortedByRecency(): SavedHost[] {
    return [...this.hostsList].sort((a, b) => b.lastConnected - a.lastConnected);
  }

  find(host: string, port: number): SavedHost | undefined {
    return this.hostsList.find((h) => h.host === host && h.port === port);
  }

  /**
   * Record a connect. Upserts by (host, port): bumps recency and merges
   * non-empty name/token/pinnedKey. Empty host is ignored (matches Swift).
   */
  record(host: string, port: number, opts: RecordOptions = {}): void {
    const trimmed = host.trim();
    if (trimmed.length === 0) return;
    const idx = this.hostsList.findIndex(
      (h) => h.host === trimmed && h.port === port,
    );
    if (idx >= 0) {
      const existing = this.hostsList[idx]!;
      existing.lastConnected = this.now();
      if (opts.name && opts.name.length > 0) existing.name = opts.name;
      if (opts.token && opts.token.length > 0) existing.token = opts.token;
      if (opts.pinnedKey && opts.pinnedKey.length > 0) {
        existing.pinnedKey = opts.pinnedKey;
      }
    } else {
      const entry: SavedHost = {
        id: randomUUID(),
        name: opts.name ?? '',
        host: trimmed,
        port,
        lastConnected: this.now(),
      };
      if (opts.token) entry.token = opts.token;
      if (opts.pinnedKey) entry.pinnedKey = opts.pinnedKey;
      this.hostsList.push(entry);
    }
    this.save();
  }

  rename(id: string, newName: string): void {
    const entry = this.hostsList.find((h) => h.id === id);
    if (!entry) return;
    entry.name = newName;
    this.save();
  }

  remove(id: string): void {
    const before = this.hostsList.length;
    this.hostsList = this.hostsList.filter((h) => h.id !== id);
    if (this.hostsList.length !== before) this.save();
  }

  private load(): void {
    const raw = this.store.getString(STORAGE_KEY);
    if (raw === undefined) return;
    try {
      const parsed: unknown = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        this.hostsList = parsed.filter(isSavedHost);
      }
    } catch {
      // Corrupt payload — start fresh rather than crash the launch path.
    }
  }

  private save(): void {
    this.store.setString(STORAGE_KEY, JSON.stringify(this.hostsList));
    this.notify();
  }
}

function isSavedHost(value: unknown): value is SavedHost {
  if (typeof value !== 'object' || value === null) return false;
  const o = value as Record<string, unknown>;
  return (
    typeof o.id === 'string' &&
    typeof o.name === 'string' &&
    typeof o.host === 'string' &&
    typeof o.port === 'number' &&
    typeof o.lastConnected === 'number'
  );
}
