/**
 * Port of the relevant slice of the Swift `AppSettings`. The RN client only
 * needs the working-directory default for new sessions plus the auto-reconnect
 * preference; the BYOK chat keys and Deepgram key live in the desktop-only
 * Chat/Speech features that are out of scope for RN-2.
 */

import { Observable } from '@/lib/observable';
import { KeyValueStore } from './storage';

const LAST_CWD_KEY = 'lastWorkingDirectory.v1';
const AUTO_RECONNECT_KEY = 'autoReconnect.v1';

export class AppSettings extends Observable {
  private lastCwd: string;
  private autoReconnectFlag: boolean;

  constructor(private readonly store: KeyValueStore) {
    super();
    this.lastCwd = store.getString(LAST_CWD_KEY) ?? '';
    this.autoReconnectFlag = store.getString(AUTO_RECONNECT_KEY) !== 'false';
  }

  /**
   * Default working directory for new sessions. Empty means "use the Mac's
   * $HOME" (the server-side default).
   */
  get lastWorkingDir(): string {
    return this.lastCwd;
  }

  setLastWorkingDir(value: string): void {
    const trimmed = value.trim();
    if (trimmed === this.lastCwd) return;
    this.lastCwd = trimmed;
    this.store.setString(LAST_CWD_KEY, trimmed);
    this.notify();
  }

  get autoReconnect(): boolean {
    return this.autoReconnectFlag;
  }

  setAutoReconnect(value: boolean): void {
    if (value === this.autoReconnectFlag) return;
    this.autoReconnectFlag = value;
    this.store.setString(AUTO_RECONNECT_KEY, value ? 'true' : 'false');
    this.notify();
  }
}
