/**
 * Port of the Swift `AgentSessionStore`. Owns one `AgentSessionModel` per agent
 * session and routes `agent_event` / `agent_session_created` / `session_closed`
 * to it, lazily creating a model on a mid-session reconnect (using the
 * session_start provider when available, else claudeCode as Swift does).
 */

import { AgentProvider, ServerMessage } from '@/protocol';
import { Observable } from '@/lib/observable';
import { AgentSessionModel } from './agent-session-model';

export class AgentSessionStore extends Observable {
  private readonly models = new Map<string, AgentSessionModel>();

  session(id: string): AgentSessionModel | undefined {
    return this.models.get(id);
  }

  handle(message: ServerMessage): void {
    switch (message.type) {
      case 'agent_session_created': {
        const info = message.session;
        if (info.agentProvider === undefined) return;
        if (!this.models.has(info.id)) {
          this.models.set(
            info.id,
            new AgentSessionModel(
              info.id,
              info.agentProvider,
              info.sessionMode ?? 'chat',
              '',
            ),
          );
          this.notify();
        }
        break;
      }
      case 'agent_event': {
        if (!this.models.has(message.sessionId)) {
          let provider: AgentProvider = 'claudeCode';
          if (message.event.type === 'session_start') {
            provider = message.event.provider;
          }
          this.models.set(
            message.sessionId,
            new AgentSessionModel(message.sessionId, provider, 'chat', ''),
          );
          this.notify();
        }
        this.models.get(message.sessionId)!.apply(message.event);
        break;
      }
      case 'session_closed':
        if (this.models.delete(message.sessionId)) this.notify();
        break;
      default:
        break;
    }
  }
}
