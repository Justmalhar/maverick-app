// client/Sources/App/ContentView.swift
import SwiftUI

// Wrapper that owns the TerminalViewController so InputToolbar can reference it.
struct TerminalWithToolbarView: View {
    let sessionId: UUID
    @State private var terminalVC = TerminalViewController()
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection

    var body: some View {
        VStack(spacing: 0) {
            TerminalContainerView(sessionId: sessionId, terminalVC: terminalVC)
                .ignoresSafeArea(.keyboard)
            InputToolbar(terminalVC: terminalVC)
        }
    }
}

struct ContentView: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionStore.self) var store

    var body: some View {
        if connection.state == .connected {
            connectedView
        } else {
            ConnectionView()
        }
    }

    private var connectedView: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                SessionTabBar()
                if let id = store.activeSessionId {
                    TerminalWithToolbarView(sessionId: id)
                        .id(id)
                } else {
                    emptyState
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("No active session")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("Tap + above to create a new shell session on your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}
