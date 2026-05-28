// server/Sources/CodexAdapter.swift
import Foundation
import MaverickProtocol

/// Translates `codex --json` stdout lines into canonical `AgentEvent` values.
///
/// Codex does not expose a hook system; tool permission events are represented
/// as a static `.statusBadge("Auto-approved", .info)` emitted alongside each
/// toolCallStart in the same return array.
///
/// Tool call ID correlation: `pendingToolIDs` maps a stable Codex key to the UUID
/// generated at toolCallStart so the matching toolCallComplete carries the same ID.
/// The adapter is used from AgentSession's serial outputQueue — no lock needed.
final class CodexAdapter: AgentEventNormalizing {

    private var pendingToolIDs: [String: String] = [:]

    // MARK: - Stream normalization

    func normalize(streamLine: Data) -> [AgentEvent] {
        guard !streamLine.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: streamLine) as? [String: Any],
              let type = obj["type"] as? String
        else { return [] }

        switch type {
        case "output":
            guard let text = obj["text"] as? String, !text.isEmpty else { return [] }
            return [.tokenDelta(text: text)]

        case "message":
            guard (obj["role"] as? String) == "assistant",
                  let content = obj["content"] as? String, !content.isEmpty
            else { return [] }
            return [.tokenDelta(text: content)]

        case "tool":
            let name = obj["name"] as? String ?? ""
            let stableKey = (obj["id"] as? String) ?? name
            let id = UUID().uuidString
            pendingToolIDs[stableKey] = id
            let inputDict = obj["input"] as? [String: Any]
            let event = ToolCallEvent(
                id: id,
                tool: codexToolKind(from: name),
                inputSummary: summarizeInput(name: name, input: inputDict),
                result: nil,
                error: nil,
                durationMs: nil,
                fileDiffs: nil,
                effort: nil
            )
            return [.toolCallStart(event), .statusBadge(text: "Auto-approved", kind: .info)]

        case "tool_result":
            let name = obj["name"] as? String ?? ""
            let stableKey = (obj["id"] as? String) ?? name
            let id = pendingToolIDs.removeValue(forKey: stableKey) ?? UUID().uuidString
            let output = obj["output"] as? String
            let durationMs = obj["duration"] as? Int
            let event = ToolCallEvent(
                id: id,
                tool: codexToolKind(from: name),
                inputSummary: "",
                result: output,
                error: nil,
                durationMs: durationMs,
                fileDiffs: nil,
                effort: nil
            )
            return [.toolCallComplete(event)]

        case "done":
            let cost = obj["cost"] as? Double
            return [.turnStop(cost: cost, inputTokens: nil, outputTokens: nil, effortLevel: nil)]

        case "error":
            if let msg = obj["message"] as? String {
                NSLog("[CodexAdapter] error from codex: %@", msg)
            }
            return [.sessionError(.unknown)]

        default:
            return []
        }
    }

    // MARK: - Hook normalization (unsupported)

    func normalize(hookPayload: [String: Any]) -> [AgentEvent] { [] }

    // MARK: - Private helpers

    private func codexToolKind(from name: String) -> ToolKind {
        switch name.lowercased() {
        case "bash", "shell", "run_command": return .bash
        case "read_file", "read":            return .read
        case "write_file", "write":          return .write
        case "list_directory", "ls":         return .glob
        case "search", "grep":               return .grep
        case "web_fetch", "fetch":           return .webFetch
        case "web_search", "search_web":     return .webSearch
        default:                             return .custom(name)
        }
    }

    private func summarizeInput(name: String, input: [String: Any]?) -> String {
        guard let input else { return name }
        if let cmd = input["command"] as? String {
            return String(cmd.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        }
        if let path = input["path"] as? String { return path }
        if let file = input["file_path"] as? String { return file }
        if let q = input["query"] as? String { return q }
        for (_, v) in input {
            if let s = v as? String { return String(s.prefix(120)) }
        }
        return name
    }
}
