// server/Sources/HermesAdapter.swift
import Foundation
import MaverickProtocol

/// Translates `hermes` stdout into canonical `AgentEvent` values via heuristics.
/// Hermes does not expose a hook system.
final class HermesAdapter: AgentEventNormalizing {

    // MARK: - Stream normalization

    func normalize(streamLine: Data) -> AgentEvent? {
        guard !streamLine.isEmpty else { return nil }
        let trimmed = streamLine
            .split(separator: UInt8(ascii: "\r"), omittingEmptySubsequences: true)
            .last ?? streamLine[...]
        guard !trimmed.isEmpty else { return nil }

        if let obj = try? JSONSerialization.jsonObject(with: Data(trimmed)) as? [String: Any] {
            // Hermes may use role-qualified messages: { "role":"assistant", "content":"..." }
            if (obj["role"] as? String) == "assistant",
               let text = obj["content"] as? String, !text.isEmpty {
                return .tokenDelta(text: text)
            }
            if let text = obj["content"] as? String, !text.isEmpty {
                return .tokenDelta(text: text)
            }
            if let text = obj["text"] as? String, !text.isEmpty {
                return .tokenDelta(text: text)
            }
            if let text = obj["message"] as? String, !text.isEmpty {
                return .tokenDelta(text: text)
            }
            if let _ = obj["error"] as? String {
                return .sessionError(.unknown)
            }
            if let done = obj["done"] as? Bool, done {
                return .turnStop(cost: nil, inputTokens: nil, outputTokens: nil, effortLevel: nil)
            }
        }

        guard let text = String(data: Data(trimmed), encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return .tokenDelta(text: text + "\n")
    }

    // MARK: - Hook normalization (unsupported)

    func normalize(hookPayload: [String: Any]) -> AgentEvent? { nil }
}
