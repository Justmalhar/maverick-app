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

/// Tabbed session screen pushed from the Sessions list:
///   [ Chat | Files | Diff ]
/// Chat keeps the existing terminal + toolbar; Files hosts the project
/// explorer; Diff hosts the git status / diff viewer when the session's cwd
/// is a git repo.
struct TerminalScreen: View {
    let sessionId: UUID
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionHistory.self) var sessionHistory
    @Environment(AppSettings.self) var settings
    @Environment(ProjectIndexModel.self) var projectIndex
    @Environment(GitStatusModel.self) var gitStatus
    @Environment(\.dismiss) var dismiss

    @State private var terminalVC = TerminalViewController()
    @State private var selectedTab: Tab = .chat

    enum Tab: String, CaseIterable, Identifiable {
        case chat = "Chat"
        case files = "Files"
        case diff = "Diff"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .chat:  return "ellipsis.message.fill"
            case .files: return "folder.fill"
            case .diff:  return "arrow.triangle.branch"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Group {
                switch selectedTab {
                case .chat:
                    chatTab
                case .files:
                    FileExplorerView(rootPath: cwd, onInsertReference: insertReference)
                case .diff:
                    GitDiffView(repoPath: cwd)
                }
            }
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

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(selectedTab == tab ? Theme.onAccent : Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(Color.white.opacity(0.95))
                        } else {
                            Color.clear.liquidGlassCapsule()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Theme.stroke).frame(height: 0.5), alignment: .bottom)
    }

    private var chatTab: some View {
        VStack(spacing: 0) {
            TerminalContainerView(sessionId: sessionId, terminalVC: terminalVC)
                .ignoresSafeArea(.keyboard)
            InputToolbar(terminalVC: terminalVC)
        }
    }

    // MARK: - Helpers

    /// Resolves the cwd for this session — prefers the **live** cwd reported
    /// by the shell via OSC 7 (so the Files tab follows `cd`), then falls
    /// back to the recorded launch cwd from history, then the user's last
    /// folder, then `~`.
    private var cwd: String {
        if let live = store.sessionCwds[sessionId], !live.isEmpty {
            return live
        }
        if let recorded = sessionHistory.entry(named: sessionName)?.cwd, !recorded.isEmpty {
            return recorded
        }
        let last = settings.lastWorkingDir
        return last.isEmpty ? "~" : last
    }

    private var sessionName: String {
        store.sessions.first(where: { $0.id == sessionId })?.name ?? "Session"
    }

    /// Sends a file reference (e.g. `@<relative>`) into the terminal so the
    /// agent can pull it up.
    private func insertReference(_ relativePath: String) {
        let token = "@\(relativePath) "
        terminalVC.injectText(token)
        selectedTab = .chat
    }
}
