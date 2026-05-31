/**
 * Port of the Swift `DirectoryBrowserModel` + its tiny `LRUCache`. Drives the
 * folder picker: correlates `list_directory` replies by requestId, caches the
 * most recent listings (bounded LRU, 30s TTL), surfaces a connection-down error
 * immediately, and times out a stuck request after 8s.
 *
 * `now` and the timer pair are injected so the cache TTL and timeout are
 * deterministic in tests.
 */

import { MaverickClient } from '@/app/maverick-client';
import { Observable } from '@/lib/observable';
import { DirectoryEntry, ServerMessage } from '@/protocol';

export type BrowserState =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'loaded' }
  | { kind: 'error'; message: string };

interface CacheEntry {
  path: string;
  entries: DirectoryEntry[];
  timestamp: number;
}

export class LRUCache<K, V> {
  private readonly dict = new Map<K, V>();
  private order: K[] = [];

  constructor(private readonly capacity: number) {}

  get(key: K): V | undefined {
    const v = this.dict.get(key);
    if (v === undefined) return undefined;
    this.order = this.order.filter((k) => k !== key);
    this.order.push(key);
    return v;
  }

  set(key: K, value: V): void {
    if (this.dict.has(key)) {
      this.order = this.order.filter((k) => k !== key);
    } else if (this.order.length >= this.capacity) {
      const oldest = this.order.shift();
      if (oldest !== undefined) this.dict.delete(oldest);
    }
    this.dict.set(key, value);
    this.order.push(key);
  }

  get size(): number {
    return this.dict.size;
  }
}

const TTL_MS = 30_000;
const TIMEOUT_MS = 8_000;

export type Timer = (fn: () => void, delayMs: number) => unknown;

/** Production timeout scheduler (wraps setTimeout). Injected in tests. */
export function defaultTimer(fn: () => void, delayMs: number): unknown {
  return setTimeout(fn, delayMs);
}

export class DirectoryBrowserModel extends Observable {
  private path = '';
  private entryList: DirectoryEntry[] = [];
  private currentState: BrowserState = { kind: 'idle' };
  private showHiddenFlag = false;

  private allEntries: DirectoryEntry[] = [];
  private pendingRequest: string | null = null;
  private readonly cache = new LRUCache<string, CacheEntry>(64);
  private readonly prefetchKeys = new Set<string>();

  constructor(
    private readonly client: MaverickClient,
    private readonly now: () => number = () => Date.now(),
    private readonly setTimer: Timer = defaultTimer,
  ) {
    super();
  }

  get currentPath(): string {
    return this.path;
  }
  get entries(): DirectoryEntry[] {
    return this.entryList;
  }
  get state(): BrowserState {
    return this.currentState;
  }
  get showHidden(): boolean {
    return this.showHiddenFlag;
  }
  setShowHidden(value: boolean): void {
    if (value === this.showHiddenFlag) return;
    this.showHiddenFlag = value;
    this.recomputeFiltered();
    this.notify();
  }

  navigate(path: string | null): void {
    const trimmed = path?.trim();
    // Empty / null → home: send no `path` (the server defaults to $HOME).
    const normalized =
      trimmed !== undefined && trimmed.length > 0 ? trimmed : undefined;
    const key = normalized ?? '~';

    const hit = this.cache.get(key);
    if (hit !== undefined && this.now() - hit.timestamp < TTL_MS) {
      this.path = hit.path;
      this.allEntries = hit.entries;
      this.recomputeFiltered();
      this.currentState = { kind: 'loaded' };
      this.notify();
      return;
    }

    if (this.client.state !== 'connected') {
      this.currentState = {
        kind: 'error',
        message: 'Not connected to your Mac. Reconnecting…',
      };
      this.notify();
      return;
    }

    this.currentState = { kind: 'loading' };
    const req = this.client.requestId();
    this.pendingRequest = req;
    this.notify();
    this.client.listDirectory(req, normalized);

    this.setTimer(() => {
      if (this.pendingRequest === req) {
        this.pendingRequest = null;
        this.currentState = {
          kind: 'error',
          message: 'Request timed out. Pull down to retry.',
        };
        this.notify();
      }
    }, TIMEOUT_MS);
  }

  navigateUp(): void {
    const idx = this.path.lastIndexOf('/');
    const parent = idx > 0 ? this.path.slice(0, idx) : '/';
    this.navigate(parent);
  }

  /** Pre-warm the home listing as soon as the socket reaches connected. */
  preflight(): void {
    const req = this.client.requestId();
    this.prefetchKeys.add(req);
    this.client.listDirectory(req, undefined);
  }

  handle(message: ServerMessage): void {
    switch (message.type) {
      case 'directory_listing':
        this.cache.set(message.path, {
          path: message.path,
          entries: message.entries,
          timestamp: this.now(),
        });
        if (this.prefetchKeys.delete(message.requestId)) return;
        if (message.requestId !== this.pendingRequest) return;
        this.pendingRequest = null;
        this.path = message.path;
        this.allEntries = message.entries;
        this.recomputeFiltered();
        this.currentState = { kind: 'loaded' };
        this.notify();
        break;
      case 'directory_listing_failed':
        if (this.prefetchKeys.delete(message.requestId)) return;
        if (message.requestId !== this.pendingRequest) return;
        this.pendingRequest = null;
        this.currentState = { kind: 'error', message: message.message };
        this.notify();
        break;
      default:
        break;
    }
  }

  private recomputeFiltered(): void {
    this.entryList = this.showHiddenFlag
      ? this.allEntries
      : this.allEntries.filter((e) => !e.isHidden);
  }
}
