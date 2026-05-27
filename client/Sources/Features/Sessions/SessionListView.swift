// client/Sources/Features/Sessions/SessionListView.swift
import SwiftUI
import MaverickProtocol

struct SessionListView: View {
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @State private var showNewSession = false
    @State private var newName = ""

    var body: some View {
        @Bindable var store = store
        List(store.sessions, selection: $store.activeSessionId) { session in
            Label(session.name, systemImage: "terminal")
                .tag(session.id)
                .swipeActions(edge: .trailing) {
                    Button("Close", role: .destructive) {
                        connection.send(.closeSession(sessionId: session.id))
                    }
                }
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("", systemImage: "plus") { showNewSession = true }
            }
        }
        .alert("New Session", isPresented: $showNewSession) {
            TextField("Name", text: $newName)
            Button("Create") {
                guard !newName.isEmpty else { return }
                connection.send(.createSession(name: newName, shell: "/bin/zsh"))
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
        .onAppear {
            connection.send(.listSessions)
        }
    }
}
