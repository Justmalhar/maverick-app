// client/Sources/Features/Terminal/TerminalContainerView.swift
import SwiftUI
import MaverickProtocol

struct TerminalContainerView: UIViewControllerRepresentable {
    let sessionId: UUID
    let terminalVC: TerminalViewController
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @Environment(ThemeStore.self) var themeStore

    func makeUIViewController(context: Context) -> TerminalViewController {
        terminalVC.onInput = { data in
            connection.send(.input(sessionId: sessionId, data: data.base64EncodedString()))
        }
        terminalVC.onResize = { cols, rows in
            connection.send(.resize(sessionId: sessionId, cols: cols, rows: rows))
        }
        store.registerOutputHandler(sessionId: sessionId) { data in
            terminalVC.feed(data: data)
        }
        connection.send(.attachSession(sessionId: sessionId))
        // Apply initial theme.
        terminalVC.applyTheme(themeStore.current)
        return terminalVC
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {
        // Re-apply theme on theme switch.
        uiViewController.applyTheme(themeStore.current)
    }
}
