// client/Sources/Design/AppTheme.swift
import SwiftUI

struct AppTheme: Codable, Identifiable, Equatable, Hashable {
    let name: String
    let type: String                   // "dark" or "light"
    let colors: UIColors
    let terminal: TerminalPalette

    var id: String { name }
    var isDark: Bool { type == "dark" }

    struct UIColors: Codable, Equatable, Hashable {
        let foreground: String
        let descriptionForeground: String?
        let errorForeground: String?
        let editorBackground: String?
        let sideBarBackground: String?
        let titleBarActiveBackground: String?
        let panelBackground: String?
        let buttonBackground: String?
        let buttonForeground: String?
        let inputBackground: String?
        let inputBorder: String?
        let tabBorder: String?
        let focusBorder: String?

        enum CodingKeys: String, CodingKey {
            case foreground
            case descriptionForeground
            case errorForeground
            case editorBackground = "editor.background"
            case sideBarBackground = "sideBar.background"
            case titleBarActiveBackground = "titleBar.activeBackground"
            case panelBackground = "panel.background"
            case buttonBackground = "button.background"
            case buttonForeground = "button.foreground"
            case inputBackground = "input.background"
            case inputBorder = "input.border"
            case tabBorder = "tab.border"
            case focusBorder
        }
    }

    struct TerminalPalette: Codable, Equatable, Hashable {
        let background: String
        let foreground: String
        let cursor: String?
        let black: String
        let red: String
        let green: String
        let yellow: String
        let blue: String
        let magenta: String
        let cyan: String
        let white: String
        let brightBlack: String
        let brightRed: String
        let brightGreen: String
        let brightYellow: String
        let brightBlue: String
        let brightMagenta: String
        let brightCyan: String
        let brightWhite: String

        var ansi16: [String] {
            [black, red, green, yellow, blue, magenta, cyan, white,
             brightBlack, brightRed, brightGreen, brightYellow,
             brightBlue, brightMagenta, brightCyan, brightWhite]
        }
    }

    // MARK: - SwiftUI color accessors
    // These map theme JSON to the semantic slots we use throughout the app.

    var bg: Color           { Color(hex: colors.editorBackground ?? terminal.background) }
    var bgElevated: Color   { Color(hex: colors.sideBarBackground ?? colors.panelBackground ?? terminal.background) }
    var surface: Color      { Color(hex: colors.inputBackground ?? colors.panelBackground ?? terminal.background).opacity(0.6) }
    var stroke: Color       { Color(hex: colors.inputBorder ?? colors.tabBorder ?? "#27272a") }
    var textPrimary: Color  { Color(hex: colors.foreground) }
    var textSecondary: Color { Color(hex: colors.descriptionForeground ?? colors.foreground).opacity(0.65) }
    var textTertiary: Color { Color(hex: colors.descriptionForeground ?? colors.foreground).opacity(0.40) }
    var accent: Color       { Color(hex: colors.buttonBackground ?? colors.focusBorder ?? colors.foreground) }
    var onAccent: Color     { Color(hex: colors.buttonForeground ?? "#000000") }
    var danger: Color       { Color(hex: colors.errorForeground ?? "#f87171") }
    var terminalBg: Color   { Color(hex: terminal.background) }
    var terminalFg: Color   { Color(hex: terminal.foreground) }
    var cursor: Color       { Color(hex: terminal.cursor ?? terminal.foreground) }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8)  & 0xFF) / 255
        let b = Double(rgb         & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        self.init(
            red:   CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8)  & 0xFF) / 255,
            blue:  CGFloat(rgb         & 0xFF) / 255,
            alpha: 1
        )
    }
}
