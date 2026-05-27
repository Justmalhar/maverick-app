// client/Sources/App/ContentView.swift
import SwiftUI
import MaverickProtocol

struct ContentView: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionStore.self) var store

    @State private var path = NavigationPath()
    @State private var showSettings = false

    var body: some View {
        if connection.state == .connected {
            NavigationStack(path: $path) {
                SessionsListView(path: $path, showSettings: $showSettings)
                    .navigationDestination(for: UUID.self) { sessionId in
                        TerminalScreen(sessionId: sessionId)
                    }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .sheet(isPresented: $showSettings) { SettingsSheet() }
        } else {
            ConnectionView()
        }
    }
}

/// Single-session terminal screen pushed from the Sessions list.
struct TerminalScreen: View {
    let sessionId: UUID
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @Environment(\.dismiss) var dismiss

    @State private var terminalVC = TerminalViewController()

    var body: some View {
        VStack(spacing: 0) {
            TerminalContainerView(sessionId: sessionId, terminalVC: terminalVC)
                .ignoresSafeArea(.keyboard)
            InputToolbar(terminalVC: terminalVC)
        }
        .background(Theme.bg)
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    connection.send(.closeSession(sessionId: sessionId))
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                }
                .tint(Theme.danger)
            }
        }
        .onAppear {
            store.activeSessionId = sessionId
        }
        .onChange(of: store.sessions) { _, newValue in
            // If the active session disappears (server closed it), pop back.
            if !newValue.contains(where: { $0.id == sessionId }) {
                dismiss()
            }
        }
    }

    private var sessionName: String {
        store.sessions.first(where: { $0.id == sessionId })?.name ?? "Session"
    }
}
