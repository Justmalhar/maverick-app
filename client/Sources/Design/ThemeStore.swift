// client/Sources/Design/ThemeStore.swift
import Foundation
import Observation

@Observable
final class ThemeStore {
    private(set) var themes: [AppTheme] = []
    var current: AppTheme

    private let key = "selectedTheme.v1"
    private static let defaultName = "Maverick Dark"

    init() {
        let loaded = Self.loadBundled()
        self.themes = loaded
        let savedName = UserDefaults.standard.string(forKey: key) ?? Self.defaultName
        self.current = loaded.first { $0.name == savedName }
            ?? loaded.first { $0.name == Self.defaultName }
            ?? loaded.first
            ?? Self.fallback
    }

    func select(_ theme: AppTheme) {
        current = theme
        UserDefaults.standard.set(theme.name, forKey: key)
    }

    private static func loadBundled() -> [AppTheme] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Themes") else {
            return []
        }
        let decoder = JSONDecoder()
        let parsed = urls.compactMap { url -> AppTheme? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(AppTheme.self, from: data)
        }
        return parsed.sorted { lhs, rhs in
            // Maverick themes first, then alphabetical
            let lhsMaverick = lhs.name.hasPrefix("Maverick")
            let rhsMaverick = rhs.name.hasPrefix("Maverick")
            if lhsMaverick != rhsMaverick { return lhsMaverick }
            return lhs.name < rhs.name
        }
    }

    /// Used if no bundled themes are found (e.g. tests).
    private static var fallback: AppTheme {
        AppTheme(
            name: "Maverick Dark",
            type: "dark",
            colors: .init(
                foreground: "#f5f5f7",
                descriptionForeground: "#71717a",
                errorForeground: "#f87171",
                editorBackground: "#000000",
                sideBarBackground: "#0a0a0a",
                titleBarActiveBackground: "#050505",
                panelBackground: "#0a0a0a",
                buttonBackground: "#fafafa",
                buttonForeground: "#000000",
                inputBackground: "#0d0d10",
                inputBorder: "#27272a",
                tabBorder: "#18181b",
                focusBorder: "#ffffff"
            ),
            terminal: .init(
                background: "#000000",
                foreground: "#f5f5f7",
                cursor: "#ffffff",
                black: "#18181b",
                red: "#ef4444",
                green: "#22c55e",
                yellow: "#eab308",
                blue: "#3b82f6",
                magenta: "#a855f7",
                cyan: "#06b6d4",
                white: "#e5e5e5",
                brightBlack: "#52525b",
                brightRed: "#f87171",
                brightGreen: "#4ade80",
                brightYellow: "#facc15",
                brightBlue: "#60a5fa",
                brightMagenta: "#c084fc",
                brightCyan: "#22d3ee",
                brightWhite: "#fafafa"
            )
        )
    }
}
