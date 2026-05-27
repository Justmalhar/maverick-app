// server/Sources/SessionManager.swift
import Foundation
import MaverickProtocol

actor SessionManager {
    private var sessions: [UUID: PTYSession] = [:]
    private var onSessionClosed: ((UUID) -> Void)?

    func createSession(name: String, shell: String = "/bin/zsh", cwd: String? = nil) throws -> SessionInfo {
        let session = PTYSession(name: name, shell: shell, cwd: cwd)
        session.onExit = { [weak self, id = session.info.id] in
            Task { await self?.handleExit(id: id) }
        }
        try session.start()
        sessions[session.info.id] = session
        return session.info
    }

    func listSessions() -> [SessionInfo] {
        sessions.values.map(\.info).sorted { $0.createdAt < $1.createdAt }
    }

    func getScrollback(sessionId: UUID) -> Data? {
        sessions[sessionId]?.getScrollback()
    }

    func write(sessionId: UUID, data: Data) {
        sessions[sessionId]?.write(data)
    }

    func resize(sessionId: UUID, cols: UInt16, rows: UInt16) {
        sessions[sessionId]?.resize(cols: cols, rows: rows)
    }

    func addOutputObserver(sessionId: UUID, clientId: UUID, handler: @escaping (Data) -> Void) {
        sessions[sessionId]?.addObserver(id: clientId, handler: handler)
    }

    func removeOutputObserver(sessionId: UUID, clientId: UUID) {
        sessions[sessionId]?.removeObserver(id: clientId)
    }

    func closeSession(id: UUID) {
        sessions[id]?.terminate()
        sessions.removeValue(forKey: id)
        onSessionClosed?(id)
    }

    func setClosedHandler(_ handler: @escaping (UUID) -> Void) {
        onSessionClosed = handler
    }

    private func handleExit(id: UUID) {
        sessions.removeValue(forKey: id)
        onSessionClosed?(id)
    }
}
