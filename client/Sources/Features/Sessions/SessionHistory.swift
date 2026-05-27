// client/Sources/Features/Sessions/SessionHistory.swift
import Foundation
import Observation
import MaverickProtocol

/// Persists the names + timestamps of sessions the user has created so they can
/// re-create previously-used sessions in one tap. Active sessions are also
/// tracked so we can show "currently running" alongside "previous".
struct PastSession: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var firstSeen: Date
    var lastSeen: Date
    var closedAt: Date?
    /// CodingAgent.id (rawValue). Set when the session was launched via the
    /// task composer; lets "Previous" rows resume with the agent's native
    /// resume flag.
    var agentId: String?
    /// The working directory the agent was launched in.
    var cwd: String?

    var isClosed: Bool { closedAt != nil }
}

@Observable
final class SessionHistory {
    private(set) var entries: [PastSession] = []
    private let key = "sessionHistory.v1"

    init() { load() }

    /// Returns the most recent occurrence of each closed-only session name,
    /// excluding names that are also currently active (so a re-opened session
    /// doesn't show up twice).
    func previous(excluding activeNames: Set<String>) -> [PastSession] {
        let closed = entries.filter { $0.isClosed && !activeNames.contains($0.name) }
        // Dedupe by name (most recent wins).
        var seen: [String: PastSession] = [:]
        for entry in closed.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            if seen[entry.name] == nil { seen[entry.name] = entry }
        }
        return Array(seen.values).sorted { $0.lastSeen > $1.lastSeen }
    }

    func handle(_ message: ServerMessage) {
        switch message {
        case .sessionCreated(let info):
            recordSeen(info)
        case .sessionList(let infos):
            for info in infos { recordSeen(info) }
        case .sessionClosed(let id):
            markClosed(id: id)
        default: break
        }
    }

    func remove(_ entry: PastSession) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Records the agent + cwd a session was launched with so we can resume
    /// later with the agent's native --continue / -c flag.
    func recordLaunchContext(sessionId: UUID, agent: CodingAgent, cwd: String?) {
        guard let idx = entries.firstIndex(where: { $0.id == sessionId }) else { return }
        entries[idx].agentId = agent.id
        entries[idx].cwd = cwd
        save()
    }

    func entry(named name: String) -> PastSession? {
        entries.filter { $0.name == name }.sorted { $0.lastSeen > $1.lastSeen }.first
    }

    func clearAllClosed() {
        entries.removeAll { $0.isClosed }
        save()
    }

    // MARK: - Private

    private func recordSeen(_ info: SessionInfo) {
        if let idx = entries.firstIndex(where: { $0.id == info.id }) {
            entries[idx].lastSeen = Date()
            entries[idx].closedAt = nil  // re-opened
        } else {
            entries.append(PastSession(id: info.id, name: info.name, firstSeen: info.createdAt, lastSeen: Date(), closedAt: nil))
        }
        save()
    }

    private func markClosed(id: UUID) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].closedAt = Date()
        entries[idx].lastSeen = Date()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([PastSession].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
