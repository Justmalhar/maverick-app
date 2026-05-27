// client/Sources/Features/Tasks/CodingAgent.swift
import Foundation

enum CodingAgent: String, CaseIterable, Identifiable, Codable, Hashable {
    case claudeCode  = "Claude Code"
    case codex       = "Codex"
    case antigravity = "Antigravity"
    case opencode    = "OpenCode"
    case hermes      = "Hermes Agent"

    var id: String { rawValue }

    /// Name of the SVG asset in `Agents.xcassets`. The names match lobe-icons.
    var assetName: String {
        switch self {
        case .claudeCode:  return "claudecode"
        case .codex:       return "codex"
        case .antigravity: return "antigravity"
        case .opencode:    return "opencode"
        case .hermes:      return "hermesagent"
        }
    }

    /// Default CLI binary. Users can override this per-agent in Settings to
    /// support custom installs (e.g. `clauded`, a wrapper, or an alias).
    var defaultBinary: String {
        switch self {
        case .claudeCode:  return "claude"
        case .codex:       return "codex"
        case .antigravity: return "antigravity"
        case .opencode:    return "opencode"
        case .hermes:      return "hermes"
        }
    }
}
