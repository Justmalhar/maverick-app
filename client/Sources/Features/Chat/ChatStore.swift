// client/Sources/Features/Chat/ChatStore.swift
import Foundation
import Observation

// MARK: - Models

struct ChatMessage: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var role: MessageRole
    var content: String
    var timestamp: Date = Date()

    enum MessageRole: String, Codable {
        case user, assistant, system
    }
}

struct ChatConversation: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String = "New Chat"
    var messages: [ChatMessage] = []
    var modelId: String
    var systemPrompt: String?       // injected as role:system on every send
    var assistantName: String?      // display name of the persona (for subtitle)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var lastMessage: ChatMessage? { messages.last(where: { $0.role != .system }) }
    var preview: String { String((lastMessage?.content ?? "No messages yet").prefix(100)) }
}

// MARK: - Store

@Observable
final class ChatStore {
    var conversations: [ChatConversation] = []
    var streamingConversationId: UUID? = nil

    private let key = "chatConversations.v1"

    init() { load() }

    @discardableResult
    func newConversation(model: String, systemPrompt: String? = nil, assistantName: String? = nil) -> UUID {
        var conv = ChatConversation(modelId: model)
        conv.systemPrompt = systemPrompt
        conv.assistantName = assistantName
        conversations.insert(conv, at: 0)
        save()
        return conv.id
    }

    func delete(id: UUID) {
        conversations.removeAll { $0.id == id }
        save()
    }

    func deleteAll(ids: Set<UUID>) {
        conversations.removeAll { ids.contains($0.id) }
        save()
    }

    func updateTitle(_ title: String, for id: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].title = title
        save()
    }

    func updateModel(_ model: String, for id: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].modelId = model
        save()
    }

    func updateSystemPrompt(_ prompt: String?, assistantName: String?, for id: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[idx].systemPrompt = prompt
        conversations[idx].assistantName = assistantName
        save()
    }

    // MARK: - Send

    func send(_ text: String, to conversationId: UUID, settings: AppSettings) async {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }

        let userMsg = ChatMessage(role: .user, content: text)
        conversations[idx].messages.append(userMsg)
        conversations[idx].updatedAt = Date()

        // Placeholder for the streaming assistant response
        let assistantMsgId = UUID()
        conversations[idx].messages.append(
            ChatMessage(id: assistantMsgId, role: .assistant, content: "")
        )
        guard let assistantIdx = conversations[idx].messages.firstIndex(where: { $0.id == assistantMsgId }) else { return }

        await MainActor.run { streamingConversationId = conversationId }

        do {
            let base = settings.chatBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let baseURL = base.isEmpty ? "https://api.openai.com/v1" : base.hasSuffix("/") ? String(base.dropLast()) : base
            guard let url = URL(string: baseURL + "/chat/completions") else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("Bearer \(settings.chatAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var msgs = conversations[idx].messages
                .filter { $0.id != assistantMsgId }
                .map { ["role": $0.role.rawValue, "content": $0.content] }
            // Prepend system prompt as the first message if one is configured
            if let prompt = conversations[idx].systemPrompt, !prompt.isEmpty {
                msgs.insert(["role": "system", "content": prompt], at: 0)
            }

            let body: [String: Any] = [
                "model": conversations[idx].modelId,
                "messages": msgs,
                "stream": true
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            var accumulated = ""
            let (asyncBytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in asyncBytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = String(line.dropFirst(6))
                guard payload != "[DONE]" else { break }
                guard let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let delta = choices.first?["delta"] as? [String: Any],
                      let chunk = delta["content"] as? String
                else { continue }
                accumulated += chunk
                let snapshot = accumulated
                await MainActor.run {
                    conversations[idx].messages[assistantIdx].content = snapshot
                }
            }

            // Auto-title from first user message
            await MainActor.run {
                if conversations[idx].title == "New Chat", !text.isEmpty {
                    conversations[idx].title = String(text.prefix(60))
                }
                conversations[idx].updatedAt = Date()
                save()
            }
        } catch {
            await MainActor.run {
                let errText = "Error: \(error.localizedDescription)"
                conversations[idx].messages[assistantIdx].content = errText
                save()
            }
        }

        await MainActor.run { streamingConversationId = nil }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ChatConversation].self, from: data)
        else { return }
        conversations = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
