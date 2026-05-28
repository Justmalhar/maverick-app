// client/Sources/Features/Agent/AgentSessionStore.swift
import Foundation
import MaverickProtocol

@Observable
final class AgentSessionStore {
    private(set) var sessions: [UUID: AgentSessionModel] = [:]

    func handle(_ message: ServerMessage) {
        switch message {
        case .agentSessionCreated(let info):
            guard let provider = info.agentProvider else { return }
            if sessions[info.id] == nil {
                sessions[info.id] = AgentSessionModel(
                    sessionId: info.id,
                    provider: provider,
                    mode: info.sessionMode ?? .chat,
                    cwd: ""
                )
            }

        case .agentEvent(let sessionId, let event):
            if sessions[sessionId] == nil {
                // `agentSessionCreated` should precede the first `agentEvent` in normal flow.
                // If it doesn't (reconnect mid-session), create a stub using the provider from
                // `sessionStart` if this IS the sessionStart event; otherwise fall back to
                // .claudeCode (apply() will correct it when sessionStart arrives).
                let provider: AgentProvider
                if case .sessionStart(_, let p, _, _, _) = event { provider = p }
                else { provider = .claudeCode }
                sessions[sessionId] = AgentSessionModel(
                    sessionId: sessionId, provider: provider, mode: .chat, cwd: ""
                )
            }
            sessions[sessionId]?.apply(event)

        case .sessionClosed(let sessionId):
            sessions.removeValue(forKey: sessionId)

        default:
            break
        }
    }

    func session(for id: UUID) -> AgentSessionModel? {
        sessions[id]
    }
}
