// server/Sources/OpenCodeAdapter.swift
import Foundation
import MaverickProtocol

/// Translates `opencode run` stdout into canonical `AgentEvent` values via heuristics.
/// OpenCode does not expose a hook system.
final class OpenCodeAdapter: AgentEventNormalizing {

    // MARK: - Stream normalization

    func normalize(streamLine: Data) -> [AgentEvent] {
        guard !streamLine.isEmpty else { return [] }
        // Strip a single trailing \r (CRLF line endings) without discarding mid-line content.
        var line = streamLine[...]
        if line.last == UInt8(ascii: "\r") { line = line.dropLast() }
        guard !line.isEmpty else { return [] }

        if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
            if let text = obj["content"] as? String, !text.isEmpty {
                return [.tokenDelta(text: text)]
            }
            if let text = obj["text"] as? String, !text.isEmpty {
                return [.tokenDelta(text: text)]
            }
            if let text = obj["message"] as? String, !text.isEmpty {
                return [.tokenDelta(text: text)]
            }
            if let errMsg = obj["error"] as? String {
                NSLog("[OpenCodeAdapter] error: %@", errMsg)
                return [.sessionError(.unknown)]
            }
            if let done = obj["done"] as? Bool, done {
                return [.turnStop(cost: nil, inputTokens: nil, outputTokens: nil, effortLevel: nil)]
            }
        }

        guard let text = String(data: Data(line), encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        return [.tokenDelta(text: text + "\n")]
    }

    // MARK: - Hook normalization (unsupported)

    func normalize(hookPayload: [String: Any]) -> [AgentEvent] { [] }
}
