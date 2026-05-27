// client/Sources/Features/Connection/ConnectionHistory.swift
import Foundation

struct SavedHost: Codable, Identifiable, Equatable {
    let id: UUID
    var host: String
    var port: Int
    var lastConnected: Date

    init(id: UUID = UUID(), host: String, port: Int, lastConnected: Date = Date()) {
        self.id = id
        self.host = host
        self.port = port
        self.lastConnected = lastConnected
    }
}

@Observable
final class ConnectionHistory {
    private(set) var hosts: [SavedHost] = []
    private let key = "savedHosts.v1"

    init() { load() }

    func record(host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dedupe by (host, port); update timestamp if it already exists.
        if let idx = hosts.firstIndex(where: { $0.host == trimmed && $0.port == port }) {
            hosts[idx].lastConnected = Date()
        } else {
            hosts.insert(SavedHost(host: trimmed, port: port), at: 0)
        }
        // Cap at 10 most recent
        hosts.sort { $0.lastConnected > $1.lastConnected }
        if hosts.count > 10 { hosts = Array(hosts.prefix(10)) }
        save()
    }

    func remove(_ entry: SavedHost) {
        hosts.removeAll { $0.id == entry.id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedHost].self, from: data)
        else { return }
        hosts = decoded.sorted { $0.lastConnected > $1.lastConnected }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
