// client/Sources/Features/Tasks/CodingAgent.swift
import Foundation
import SwiftUI

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

    /// Flag passed to the binary to resume the most recent conversation in
    /// the current directory. nil if the agent doesn't expose a resume flag.
    var resumeFlag: String? {
        switch self {
        case .claudeCode:  return "-c"        // claude --continue
        case .codex:       return "--resume"
        case .opencode:    return "--continue"
        case .antigravity: return nil
        case .hermes:      return nil
        }
    }

    /// Short display name for compact UI contexts like pinned agent bubbles.
    var shortName: String {
        switch self {
        case .claudeCode:  return "Claude"
        case .codex:       return "Codex"
        case .antigravity: return "Anti."
        case .opencode:    return "OpenCode"
        case .hermes:      return "Hermes"
        }
    }

    /// Per-agent accent color for avatars and active indicators.
    var accentColor: Color {
        switch self {
        case .claudeCode:  return Color(hex: "#E8632A") // Anthropic coral-orange
        case .codex:       return Color(hex: "#10B981") // OpenAI green
        case .antigravity: return Color(hex: "#7C3AED") // electric purple
        case .opencode:    return Color(hex: "#0EA5E9") // sky blue
        case .hermes:      return Color(hex: "#D97706") // amber-gold
        }
    }

    /// True when the SVG in `Agents.xcassets` carries its own brand colors
    /// (so it should render with `.original` mode and ignore any tint).
    /// False for template-style SVGs whose paths use `currentColor`.
    var isColorIcon: Bool {
        switch self {
        case .claudeCode, .codex, .antigravity, .opencode: return true
        case .hermes: return false
        }
    }
}
