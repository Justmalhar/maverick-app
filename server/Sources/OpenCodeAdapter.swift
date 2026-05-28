// server/Sources/OpenCodeAdapter.swift
import Foundation
import MaverickProtocol

/// Translates `opencode run` stdout into canonical `AgentEvent` values via heuristics.
/// OpenCode does not expose a hook system.
final class OpenCodeAdapter: AgentEventNormalizing {

    // MARK: - Stream normalization

    func normalize(streamLine: Data) -> [AgentEvent] {
        guard !streamLine.isEmpty else { return [] }
        let trimmed = streamLine
            .split(separator: UInt8(ascii: "\r"), omittingEmptySubsequences: true)
            .last ?? streamLine[...]
        guard !trimmed.isEmpty else { return [] }

        // Try JSON first — many OpenCode versions emit structured JSON lines
        if let obj = try? JSONSerialization.jsonObject(with: Data(trimmed)) as? [String: Any] {
            if let text = obj["content"] as? String, !text.isEmpty {
                return [.tokenDelta(text: text)]
            }
            if let text = obj["text"] as? String, !text.isEmpty {
                return [.tokenDelta(text: text)]
            }
            if let text = obj["message"] as? String, !text.isEmpty {
                return [.tokenDelta(text: text)]
            }
            if let _ = obj["error"] as? String {
                return [.sessionError(.unknown)]
            }
            if let done = obj["done"] as? Bool, done {
                return [.turnStop(cost: nil, inputTokens: nil, outputTokens: nil, effortLevel: nil)]
            }
            // Unrecognized JSON object — fall through to plain-text path
        }

        // Plain-text fallback: emit any non-empty line as a token delta
        guard let text = String(data: Data(trimmed), encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return [.tokenDelta(text: text + "\n")]
    }

    // MARK: - Hook normalization (unsupported)

    func normalize(hookPayload: [String: Any]) -> [AgentEvent] { [] }
}
