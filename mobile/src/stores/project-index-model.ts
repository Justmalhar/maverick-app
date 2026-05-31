/**
 * Port of the Swift `ProjectIndexModel`. Streams index chunks, dedupes by path,
 * and exposes a `children(of:)` tree query for the file explorer.
 */

import { MaverickClient } from '@/app/maverick-client';
import { Observable } from '@/lib/observable';
import { IndexEntry, ServerMessage } from '@/protocol';

export type IndexState =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'loaded' }
  | { kind: 'error'; message: string };

export class ProjectIndexModel extends Observable {
  private rootPath = '';
  private currentState: IndexState = { kind: 'idle' };
  private entryList: IndexEntry[] = [];
  private showHiddenFlag = false;

  private readonly entrySet = new Set<string>();
  private pendingRequestId: string | null = null;

  constructor(private readonly client: MaverickClient) {
    super();
  }

  get root(): string {
    return this.rootPath;
  }
  get state(): IndexState {
    return this.currentState;
  }
  get entries(): IndexEntry[] {
    return this.entryList;
  }
  get showHidden(): boolean {
    return this.showHiddenFlag;
  }
  setShowHidden(value: boolean): void {
    if (value === this.showHiddenFlag) return;
    this.showHiddenFlag = value;
    this.notify();
  }

  index(path: string, refresh = false): void {
    const trimmed = path.trim();
    if (trimmed.length === 0) return;
    if (trimmed === this.rootPath && this.currentState.kind === 'loaded' && !refresh) {
      return;
    }
    const req = this.client.requestId();
    this.pendingRequestId = req;
    this.currentState = { kind: 'loading' };
    this.entryList = [];
    this.entrySet.clear();
    this.notify();
    this.client.indexProject(req, trimmed, refresh);
  }

  handle(message: ServerMessage): void {
    switch (message.type) {
      case 'index_chunk': {
        if (message.requestId !== this.pendingRequestId) return;
        this.rootPath = message.root;
        for (const entry of message.entries) {
          if (!this.entrySet.has(entry.path)) {
            this.entrySet.add(entry.path);
            this.entryList = [...this.entryList, entry];
          }
        }
        if (message.complete) {
          this.currentState = { kind: 'loaded' };
          this.pendingRequestId = null;
        }
        this.notify();
        break;
      }
      case 'index_failed':
        if (message.requestId !== this.pendingRequestId) return;
        this.currentState = { kind: 'error', message: message.message };
        this.pendingRequestId = null;
        this.notify();
        break;
      default:
        break;
    }
  }

  /**
   * Direct children of `parent` (relative path; empty = root level), filtered
   * by the hidden toggle and sorted directories-first, case-insensitive.
   */
  children(parent: string): IndexEntry[] {
    const prefix = parent.length === 0 ? '' : parent + '/';
    return this.entryList
      .filter((entry) => {
        if (!entry.path.startsWith(prefix)) return false;
        const remainder = entry.path.slice(prefix.length);
        return remainder.length > 0 && !remainder.includes('/');
      })
      .filter((entry) => {
        if (this.showHiddenFlag) return true;
        const segments = entry.path.split('/');
        const leaf = segments[segments.length - 1]!;
        return !leaf.startsWith('.');
      })
      .sort((a, b) => {
        if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
        return a.path.localeCompare(b.path, undefined, { sensitivity: 'base' });
      });
  }
}
