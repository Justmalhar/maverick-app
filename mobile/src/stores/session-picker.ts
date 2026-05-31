/**
 * Session picker view-model — the WhatsApp-style handoff entry point. Derives
 * the categorised session list the picker screen renders from a `SessionStore`,
 * and exposes `resume` / `attach` actions over the client.
 *
 * The committed protocol exposes a single `list_sessions` → `session_list`
 * round-trip (there is no separate `session.listResumable` frame yet). We
 * categorise the returned `SessionInfo`s locally:
 *
 *   - agent sessions (agentProvider set)  → "Agents"   (resume target)
 *   - plain PTY sessions                  → "Terminals" (attach target)
 *
 * Resume re-attaches the session and switches it to chat mode (the handoff
 * gesture); attach just subscribes. Both are idempotent on the client.
 */

import { MaverickClient } from '@/app/maverick-client';
import { SessionStore } from './session-store';
import { SessionInfo } from '@/protocol';

export type SessionCategory = 'agent' | 'terminal';

export interface PickerRow {
  session: SessionInfo;
  category: SessionCategory;
  /** True when this session can be resumed in chat mode (agent sessions). */
  resumable: boolean;
}

export function categorize(session: SessionInfo): SessionCategory {
  return session.agentProvider !== undefined ? 'agent' : 'terminal';
}

export class SessionPicker {
  constructor(
    private readonly client: MaverickClient,
    private readonly store: SessionStore,
  ) {}

  /** Ask the server for the current session list. */
  refresh(): void {
    this.client.listSessions();
  }

  /** Categorised, name-sorted rows for the picker UI. */
  rows(): PickerRow[] {
    return this.store.sessions
      .map((session) => {
        const category = categorize(session);
        return { session, category, resumable: category === 'agent' };
      })
      .sort((a, b) =>
        a.session.name.localeCompare(b.session.name, undefined, {
          sensitivity: 'base',
        }),
      );
  }

  agents(): PickerRow[] {
    return this.rows().filter((r) => r.category === 'agent');
  }

  terminals(): PickerRow[] {
    return this.rows().filter((r) => r.category === 'terminal');
  }

  /** Attach (subscribe) to a session without changing its mode. */
  attach(sessionId: string): void {
    this.client.attach(sessionId);
    this.store.setActiveSessionId(sessionId);
  }

  /**
   * Resume an agent session: attach and flip it to chat mode so the handoff
   * lands the user straight in the agent timeline.
   */
  resume(sessionId: string): void {
    this.client.attach(sessionId);
    this.client.switchSessionMode(sessionId, 'chat');
    this.store.setActiveSessionId(sessionId);
  }
}
