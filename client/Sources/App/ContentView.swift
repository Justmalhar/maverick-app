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
            NavigationSplitView {
                SessionListView()
            } detail: {
                if let id = store.activeSessionId {
                    TerminalWithToolbarView(sessionId: id)
                } else {
                    ContentUnavailableView("No Session", systemImage: "terminal", description: Text("Tap + to create a session"))
                }
            }
        } else {
            ConnectionView()
        }
    }
}
