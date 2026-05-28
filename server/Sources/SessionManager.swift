// server/Sources/SessionManager.swift
import Foundation
import MaverickProtocol

actor SessionManager {
    // PTY sessions (existing)
    private var sessions: [UUID: PTYSession] = [:]

    // Agent sessions (new)
    private var agentSessions: [UUID: AgentSession] = [:]

    // Maps Claude Code's own session ID → Maverick session UUID.
    // Written when AgentSession fires a .sessionStart event; read by HookServer routing.
    private var claudeIdIndex: [String: UUID] = [:]

    private var onSessionClosed: ((UUID) -> Void)?

    // Set once after MenuBarController creates the broadcaster.
    // Captured by each AgentSession.onAgentEvent closure at creation time.
    private var broadcaster: AgentEventBroadcaster?

    // MARK: - Configuration

    func setBroadcaster(_ broadcaster: AgentEventBroadcaster) {
        self.broadcaster = broadcaster
    }

    func setClosedHandler(_ handler: @escaping (UUID) -> Void) {
        onSessionClosed = handler
    }

    // MARK: - PTY session API (unchanged)

    @discardableResult
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
        let ptyInfos = sessions.values.map(\.info)
        let agentInfos = agentSessions.values.map { s in
            SessionInfo(id: s.sessionId, name: "agent", shell: s.provider.rawValue,
                        agentProvider: s.provider, sessionMode: s.mode)
        }
        return (ptyInfos + agentInfos).sorted { $0.createdAt < $1.createdAt }
    }

    func getScrollback(sessionId: UUID) -> Data? {
        if let pty = sessions[sessionId] { return pty.getScrollback() }
        if let ag = agentSessions[sessionId] { return ag.getScrollback() }
        return nil
    }

    func write(sessionId: UUID, data: Data) {
        if let pty = sessions[sessionId] { pty.write(data) }
        else if let ag = agentSessions[sessionId] {
            if let text = String(data: data, encoding: .utf8) {
                ag.sendInput(text)
            }
        }
    }

    func resize(sessionId: UUID, cols: UInt16, rows: UInt16) {
        sessions[sessionId]?.resize(cols: cols, rows: rows)
        agentSessions[sessionId]?.resize(cols: cols, rows: rows)
    }

    func addOutputObserver(sessionId: UUID, clientId: UUID, handler: @escaping (Data) -> Void) {
        sessions[sessionId]?.addObserver(id: clientId, handler: handler)
        agentSessions[sessionId]?.addObserver(id: clientId, handler: handler)
    }

    func removeOutputObserver(sessionId: UUID, clientId: UUID) {
        sessions[sessionId]?.removeObserver(id: clientId)
        agentSessions[sessionId]?.removeObserver(id: clientId)
    }

    func closeSession(id: UUID) {
        if let pty = sessions.removeValue(forKey: id) {
            pty.terminate()
        } else if let ag = agentSessions.removeValue(forKey: id) {
            ag.terminate()
        }
        onSessionClosed?(id)
    }

    // MARK: - Agent session API

    @discardableResult
    func createAgentSession(name: String, provider: AgentProvider, cwd: String?) throws -> SessionInfo {
        let sessionId = UUID()
        let normalizer = makeNormalizer(for: provider)
        let session = AgentSession(sessionId: sessionId, provider: provider,
                                   mode: .chat, normalizer: normalizer, cwd: cwd)
        let capturedBroadcaster = broadcaster

        session.onAgentEvent = { [weak self] event in
            if case .sessionStart(let claudeId, _, _, _, _) = event {
                Task { [weak self] in await self?.registerClaudeId(claudeId, for: sessionId) }
            }
            capturedBroadcaster?.receive(event: event, for: sessionId)
        }
        session.onExit = { [weak self] in
            Task { await self?.handleAgentExit(id: sessionId) }
        }

        try session.start()
        agentSessions[sessionId] = session
        let info = SessionInfo(id: sessionId, name: name, shell: provider.rawValue,
                               agentProvider: provider, sessionMode: .chat)
        return info
    }

    func switchAgentSessionMode(sessionId: UUID, mode: SessionMode) throws {
        guard let session = agentSessions[sessionId] else { return }
        try session.switchMode(to: mode)
    }

    func sendAgentInput(sessionId: UUID, text: String) {
        agentSessions[sessionId]?.sendInput(text)
    }

    func closeAgentSession(id: UUID) {
        agentSessions.removeValue(forKey: id)?.terminate()
        onSessionClosed?(id)
    }

    /// Look up the Maverick session UUID for a Claude Code internal session ID.
    /// Returns nil if the session hasn't fired a SessionStart event yet.
    func resolveSessionId(forClaudeId claudeId: String) -> UUID? {
        claudeIdIndex[claudeId]
    }

    // MARK: - Private helpers

    private func registerClaudeId(_ claudeId: String, for maverickId: UUID) {
        claudeIdIndex[claudeId] = maverickId
    }

    private func makeNormalizer(for provider: AgentProvider) -> AgentEventNormalizing {
        switch provider {
        case .claudeCode:  return ClaudeCodeAdapter()
        case .codex:       return CodexAdapter()
        case .opencode:    return OpenCodeAdapter()
        case .antigravity: return AntigravityAdapter()
        case .hermes:      return HermesAdapter()
        }
    }

    private func handleExit(id: UUID) {
        sessions.removeValue(forKey: id)
        onSessionClosed?(id)
    }

    private func handleAgentExit(id: UUID) {
        agentSessions.removeValue(forKey: id)
        onSessionClosed?(id)
    }
}
