// client/Sources/Design/Theme.swift
import SwiftUI

enum Theme {
    // Background gradient stops
    static let bgTop    = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let bgBottom = Color(red: 0.09, green: 0.06, blue: 0.14)

    static let surface  = Color.white.opacity(0.05)
    static let stroke   = Color.white.opacity(0.10)
    static let strokeStrong = Color.white.opacity(0.18)

    // Accents
    static let accent          = Color(red: 0.20, green: 0.85, blue: 0.65) // mint
    static let accentSecondary = Color(red: 0.45, green: 0.70, blue: 1.00) // periwinkle
    static let danger          = Color(red: 1.00, green: 0.40, blue: 0.45)

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary  = Color.white.opacity(0.40)

    // Gradients
    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, Color(red: 0.15, green: 0.70, blue: 0.85)], startPoint: .leading, endPoint: .trailing)
    }
}
