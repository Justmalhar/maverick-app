// client/Sources/Features/Tasks/CodingAgent.swift
import Foundation

enum CodingAgent: String, CaseIterable, Identifiable, Codable {
    case claudeCode  = "Claude Code"
    case codex       = "Codex"
    case antigravity = "Antigravity"
    case opencode    = "OpenCode"

    var id: String { rawValue }

    /// SF Symbol shown next to the agent name.
    var iconName: String {
        switch self {
        case .claudeCode:  return "sparkles"
        case .codex:       return "chevron.left.forwardslash.chevron.right"
        case .antigravity: return "arrow.up.forward.app.fill"
        case .opencode:    return "curlybraces"
        }
    }

    /// The CLI binary that the agent runs.
    var binary: String {
        switch self {
        case .claudeCode:  return "claude"
        case .codex:       return "codex"
        case .antigravity: return "antigravity"
        case .opencode:    return "opencode"
        }
    }

    /// Builds the shell line that launches the agent with the given task.
    /// Wraps the task in single quotes and escapes embedded single quotes
    /// using the standard shell pattern: '\\''
    func command(for task: String) -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return binary }
        let escaped = trimmed.replacingOccurrences(of: "'", with: "'\\''")
        return "\(binary) '\(escaped)'"
    }

    /// Generates a short, human-readable session name from the task.
    func sessionName(for task: String) -> String {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rawValue }
        let snippet = String(trimmed.prefix(28))
        return "\(rawValue) — \(snippet)"
    }
}
