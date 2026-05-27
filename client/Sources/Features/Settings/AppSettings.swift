// client/Sources/Features/Settings/AppSettings.swift
import Foundation
import Observation

@Observable
final class AppSettings {
    private let dgKeyKey = "deepgramAPIKey.v1"
    private let agentBinariesKey = "agentBinaries.v1"
    private let lastCwdKey = "lastWorkingDirectory.v1"

    var deepgramAPIKey: String {
        didSet { UserDefaults.standard.set(deepgramAPIKey, forKey: dgKeyKey) }
    }

    /// Default working directory for new terminal sessions. Empty string means
    /// "use the Mac's $HOME" (which is the server-side default).
    var lastWorkingDir: String {
        didSet { UserDefaults.standard.set(lastWorkingDir, forKey: lastCwdKey) }
    }

    /// Per-agent CLI binary overrides. Empty/missing entries fall back to
    /// `CodingAgent.defaultBinary`. Use `binary(for:)` and `setBinary(_:for:)`.
    private(set) var agentBinaries: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(agentBinaries) {
                UserDefaults.standard.set(data, forKey: agentBinariesKey)
            }
        }
    }

    init() {
        self.deepgramAPIKey = UserDefaults.standard.string(forKey: dgKeyKey) ?? ""
        self.lastWorkingDir = UserDefaults.standard.string(forKey: lastCwdKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: agentBinariesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.agentBinaries = decoded
        } else {
            self.agentBinaries = [:]
        }
    }

    var hasDeepgramKey: Bool { !deepgramAPIKey.isEmpty }

    func binary(for agent: CodingAgent) -> String {
        let override = agentBinaries[agent.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty { return override }
        return agent.defaultBinary
    }

    func setBinary(_ value: String, for agent: CodingAgent) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == agent.defaultBinary {
            agentBinaries.removeValue(forKey: agent.id)
        } else {
            agentBinaries[agent.id] = trimmed
        }
    }

    func resetBinaries() {
        agentBinaries = [:]
    }
}
