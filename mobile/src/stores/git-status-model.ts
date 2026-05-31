/**
 * Port of the Swift `GitStatusModel`. Drives the git diff screen: holds the
 * current `GitStatus` plus a per-file diff cache keyed by `<staged?>:<file>`,
 * fetching diffs on demand and correlating replies by requestId.
 */

import { MaverickClient } from '@/app/maverick-client';
import { Observable } from '@/lib/observable';
import { GitStatus, ServerMessage } from '@/protocol';

export type GitState =
  | { kind: 'idle' }
  | { kind: 'loading' }
  | { kind: 'loaded' }
  | { kind: 'error'; message: string };

export interface DiffResult {
  text: string;
  truncated: boolean;
}

const NOT_A_REPO: GitStatus = {
  isRepo: false,
  ahead: 0,
  behind: 0,
  files: [],
};

export function diffKey(file: string, staged: boolean): string {
  return (staged ? 'S:' : 'U:') + file;
}

export class GitStatusModel extends Observable {
  private repoPath = '';
  private currentState: GitState = { kind: 'idle' };
  private currentStatus: GitStatus = NOT_A_REPO;
  private readonly diffCache = new Map<string, DiffResult>();
  private readonly pendingDiffKeys = new Set<string>();

  private pendingStatusRequestId: string | null = null;
  private readonly pendingDiffRequests = new Map<string, string>();

  constructor(private readonly client: MaverickClient) {
    super();
  }

  get path(): string {
    return this.repoPath;
  }
  get state(): GitState {
    return this.currentState;
  }
  get status(): GitStatus {
    return this.currentStatus;
  }
  diff(file: string, staged: boolean): DiffResult | undefined {
    return this.diffCache.get(diffKey(file, staged));
  }
  isDiffPending(file: string, staged: boolean): boolean {
    return this.pendingDiffKeys.has(diffKey(file, staged));
  }

  refresh(path: string): void {
    const trimmed = path.trim();
    if (trimmed.length === 0) return;
    const req = this.client.requestId();
    this.pendingStatusRequestId = req;
    this.currentState = { kind: 'loading' };
    this.repoPath = trimmed;
    this.notify();
    this.client.gitStatus(req, trimmed);
  }

  fetchDiff(file: string, staged: boolean): void {
    const key = diffKey(file, staged);
    if (this.diffCache.has(key) || this.pendingDiffKeys.has(key)) return;
    const req = this.client.requestId();
    this.pendingDiffRequests.set(req, key);
    this.pendingDiffKeys.add(key);
    this.notify();
    this.client.gitDiff(req, this.repoPath, file, staged);
  }

  handle(message: ServerMessage): void {
    switch (message.type) {
      case 'git_status_result':
        if (message.requestId !== this.pendingStatusRequestId) return;
        this.currentStatus = message.status;
        this.currentState = { kind: 'loaded' };
        this.pendingStatusRequestId = null;
        this.notify();
        break;
      case 'git_status_failed':
        if (message.requestId !== this.pendingStatusRequestId) return;
        this.currentState = { kind: 'error', message: message.message };
        this.pendingStatusRequestId = null;
        this.notify();
        break;
      case 'git_diff_result': {
        const key = this.pendingDiffRequests.get(message.requestId);
        if (key === undefined) return;
        this.pendingDiffRequests.delete(message.requestId);
        this.pendingDiffKeys.delete(key);
        this.diffCache.set(key, {
          text: message.diff,
          truncated: message.truncated,
        });
        this.notify();
        break;
      }
      case 'git_diff_failed': {
        const key = this.pendingDiffRequests.get(message.requestId);
        if (key === undefined) return;
        this.pendingDiffRequests.delete(message.requestId);
        this.pendingDiffKeys.delete(key);
        this.diffCache.set(key, {
          text: `[diff failed] ${message.message}`,
          truncated: false,
        });
        this.notify();
        break;
      }
      default:
        break;
    }
  }
}
