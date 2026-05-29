// client/Sources/Features/Settings/AppSettings.swift
import Foundation
import Observation

// MARK: - Chat assistant (persona with custom system prompt)

struct ChatAssistant: Codable, Identifiable {
    var id: UUID = UUID()
    var emoji: String = "🤖"
    var name: String
    var systemPrompt: String
    var modelOverride: String?      // nil = use global default model
}

// MARK: - AppSettings

@Observable
final class AppSettings {
    private let dgKeyKey = "deepgramAPIKey.v1"
    private let agentBinariesKey = "agentBinaries.v1"
    private let lastCwdKey = "lastWorkingDirectory.v1"
    private let chatAPIKeyKey = "chatAPIKey.v1"
    private let chatBaseURLKey = "chatBaseURL.v1"
    private let chatModelKey = "chatModel.v1"
    private let chatAssistantsKey = "chatAssistants.v1"

    var deepgramAPIKey: String {
        didSet { UserDefaults.standard.set(deepgramAPIKey, forKey: dgKeyKey) }
    }

    /// Default working directory for new terminal sessions. Empty string means
    /// "use the Mac's $HOME" (which is the server-side default).
    var lastWorkingDir: String {
        didSet { UserDefaults.standard.set(lastWorkingDir, forKey: lastCwdKey) }
    }

    /// BYOK: API key for any OpenAI-compatible endpoint.
    var chatAPIKey: String {
        didSet { UserDefaults.standard.set(chatAPIKey, forKey: chatAPIKeyKey) }
    }

    /// BYOK: Base URL for the OpenAI-compatible API (no trailing slash, no /chat/completions).
    /// Defaults to https://api.openai.com/v1 when empty.
    var chatBaseURL: String {
        didSet { UserDefaults.standard.set(chatBaseURL, forKey: chatBaseURLKey) }
    }

    /// Default model ID used when creating new chat conversations.
    var chatModel: String {
        didSet { UserDefaults.standard.set(chatModel, forKey: chatModelKey) }
    }

    /// User-defined chat personas with custom system prompts.
    private(set) var chatAssistants: [ChatAssistant] {
        didSet { saveAssistants() }
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
        self.chatAPIKey = UserDefaults.standard.string(forKey: chatAPIKeyKey) ?? ""
        self.chatBaseURL = UserDefaults.standard.string(forKey: chatBaseURLKey) ?? ""
        self.chatModel = UserDefaults.standard.string(forKey: chatModelKey).flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-4o-mini"
        if let data = UserDefaults.standard.data(forKey: agentBinariesKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.agentBinaries = decoded
        } else {
            self.agentBinaries = [:]
        }
        if let data = UserDefaults.standard.data(forKey: chatAssistantsKey),
           let decoded = try? JSONDecoder().decode([ChatAssistant].self, from: data) {
            self.chatAssistants = decoded
        } else {
            self.chatAssistants = []
        }
    }

    var hasDeepgramKey: Bool { !deepgramAPIKey.isEmpty }
    var hasChatKey: Bool { !chatAPIKey.isEmpty }

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

    // MARK: - Chat assistants CRUD

    func upsertAssistant(_ assistant: ChatAssistant) {
        if let idx = chatAssistants.firstIndex(where: { $0.id == assistant.id }) {
            chatAssistants[idx] = assistant
        } else {
            chatAssistants.append(assistant)
        }
    }

    func deleteAssistant(id: UUID) {
        chatAssistants.removeAll { $0.id == id }
    }

    func moveAssistants(from offsets: IndexSet, to destination: Int) {
        chatAssistants.move(fromOffsets: offsets, toOffset: destination)
    }

    private func saveAssistants() {
        if let data = try? JSONEncoder().encode(chatAssistants) {
            UserDefaults.standard.set(data, forKey: chatAssistantsKey)
        }
    }
}
