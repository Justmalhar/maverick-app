/**
 * AppModel — the composition root the React tree consumes via context. It owns
 * the MaverickClient and every store, subscribes to the client's ServerMessage
 * stream once, and fans each frame out to the stores that own it. This mirrors
 * the Swift app's environment objects, but with a single subscription point so
 * message routing is centralised and testable.
 */

import { MaverickClient } from './maverick-client';
import { AppSettings } from './app-settings';
import { ConnectionHistory } from './connection-history';
import { KeyValueStore, MemoryStore } from './storage';
import { SessionStore } from '@/stores/session-store';
import { AgentSessionStore } from '@/stores/agent-session-store';
import { GitStatusModel } from '@/stores/git-status-model';
import { ProjectIndexModel } from '@/stores/project-index-model';
import { DirectoryBrowserModel } from '@/stores/directory-browser-model';
import { SessionPicker } from '@/stores/session-picker';
import { ServerMessage } from '@/protocol';
import { Unsubscribe } from '@/lib/observable';

export interface AppModelOptions {
  client?: MaverickClient;
  store?: KeyValueStore;
}

export class AppModel {
  readonly client: MaverickClient;
  readonly settings: AppSettings;
  readonly history: ConnectionHistory;
  readonly sessions: SessionStore;
  readonly agents: AgentSessionStore;
  readonly git: GitStatusModel;
  readonly index: ProjectIndexModel;
  readonly directory: DirectoryBrowserModel;
  readonly picker: SessionPicker;

  private readonly unsubscribe: Unsubscribe;

  constructor(opts: AppModelOptions = {}) {
    const store = opts.store ?? new MemoryStore();
    this.client = opts.client ?? new MaverickClient();
    this.settings = new AppSettings(store);
    this.history = new ConnectionHistory(store);
    this.sessions = new SessionStore();
    this.agents = new AgentSessionStore();
    this.git = new GitStatusModel(this.client);
    this.index = new ProjectIndexModel(this.client);
    this.directory = new DirectoryBrowserModel(this.client);
    this.picker = new SessionPicker(this.client, this.sessions);

    this.unsubscribe = this.client.messages.on((msg) => this.route(msg));
  }

  private route(message: ServerMessage): void {
    this.sessions.handle(message);
    this.agents.handle(message);
    this.git.handle(message);
    this.index.handle(message);
    this.directory.handle(message);
  }

  dispose(): void {
    this.unsubscribe();
  }
}
