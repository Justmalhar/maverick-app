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
                // Late-arriving event for a session created before we registered — create on demand.
                sessions[sessionId] = AgentSessionModel(
                    sessionId: sessionId, provider: .claudeCode, mode: .chat, cwd: ""
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
