// client/Sources/Design/Theme.swift
import SwiftUI

/// Static UI chrome palette — pure monochrome (Maverick Dark style).
/// The terminal's own colors are theme-swappable via ThemeStore; UI chrome stays neutral.
enum Theme {
    // Backgrounds
    static let bg          = Color(hex: "#000000")
    static let bgElevated  = Color(hex: "#0a0a0a")
    static let surface     = Color(hex: "#0d0d10")
    static let surfaceHi   = Color(hex: "#18181b")

    // Strokes
    static let stroke         = Color.white.opacity(0.10)
    static let strokeStrong   = Color.white.opacity(0.20)

    // Text
    static let textPrimary   = Color(hex: "#fafafa")
    static let textSecondary = Color(hex: "#a1a1aa")
    static let textTertiary  = Color(hex: "#52525b")

    // Accent: white on dark, single point of contrast
    static let accent        = Color(hex: "#fafafa")
    static let onAccent      = Color(hex: "#000000")

    // Status
    static let danger        = Color(hex: "#f87171")
    static let success       = Color(hex: "#4ade80")

    // Background fill (subtle vertical gradient — barely there)
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#050505"), Color(hex: "#000000")],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    // Accent gradient (used on prominent buttons)
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#fafafa"), Color(hex: "#d4d4d8")],
            startPoint: .top, endPoint: .bottom
        )
    }
}
