// client/Sources/Features/Connection/ConnectionHistory.swift
import Foundation
import Observation

struct SavedHost: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var lastConnected: Date
    var token: String?

    init(id: UUID = UUID(), name: String = "", host: String, port: Int, lastConnected: Date = Date(), token: String? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.lastConnected = lastConnected
        self.token = token
    }

    /// User-facing label — name if set, otherwise host:port.
    var displayName: String {
        name.isEmpty ? "\(host):\(port)" : name
    }
}

@Observable
final class ConnectionHistory {
    private(set) var hosts: [SavedHost] = []
    private let key = "savedHosts.v2"

    init() { load() }

    /// Backwards-compatible accessor that mirrors the previous shape.
    var sortedByRecency: [SavedHost] {
        hosts.sorted { $0.lastConnected > $1.lastConnected }
    }

    func record(host: String, port: Int, name: String = "", token: String? = nil) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let idx = hosts.firstIndex(where: { $0.host == trimmed && $0.port == port }) {
            hosts[idx].lastConnected = Date()
            if !name.isEmpty { hosts[idx].name = name }
            if let token, !token.isEmpty { hosts[idx].token = token }
        } else {
            hosts.append(SavedHost(name: name, host: trimmed, port: port, token: token))
        }
        save()
    }

    func upsert(_ entry: SavedHost) {
        if let idx = hosts.firstIndex(where: { $0.id == entry.id }) {
            hosts[idx] = entry
        } else {
            hosts.append(entry)
        }
        save()
    }

    func rename(_ entry: SavedHost, to newName: String) {
        guard let idx = hosts.firstIndex(where: { $0.id == entry.id }) else { return }
        hosts[idx].name = newName
        save()
    }

    func remove(_ entry: SavedHost) {
        hosts.removeAll { $0.id == entry.id }
        save()
    }

    private func load() {
        // Try v2 schema first.
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedHost].self, from: data) {
            hosts = decoded
            return
        }
        // Migrate from v1 (the previous flat tuple format).
        if let data = UserDefaults.standard.data(forKey: "savedHosts.v1"),
           let legacy = try? JSONDecoder().decode([LegacyEntry].self, from: data) {
            hosts = legacy.map {
                SavedHost(id: $0.id, name: "", host: $0.host, port: $0.port, lastConnected: $0.lastConnected)
            }
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct LegacyEntry: Codable {
        let id: UUID
        var host: String
        var port: Int
        var lastConnected: Date
    }
}
