// client/Sources/App/ContentView.swift
import SwiftUI
import MaverickProtocol

// MARK: - App tabs

enum AppTab: String, CaseIterable, Identifiable {
    case agents = "Agents"
    case chats  = "Chats"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .agents: return "terminal"
        case .chats:  return "bubble.left.and.bubble.right"
        }
    }
    var selectedIcon: String {
        switch self {
        case .agents: return "terminal.fill"
        case .chats:  return "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionStore.self) var store
    @Environment(ChatStore.self) var chatStore

    @State private var agentsPath = NavigationPath()
    @State private var chatPath = NavigationPath()
    @State private var showSettings = false
    @State private var selectedTab: AppTab = .agents
    @State private var showCompose = false

    var body: some View {
        if connection.state == .connected {
            connectedView
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .sheet(isPresented: $showSettings) { SettingsSheet() }
                .sheet(isPresented: $showCompose) {
                    ComposeSheetContent(initialAgent: nil) { showCompose = false }
                }
        } else {
            ConnectionView()
        }
    }

    @ViewBuilder
    private var connectedView: some View {
        ZStack(alignment: .bottom) {
            // Both tab views always rendered to preserve navigation/scroll state.
            Group {
                NavigationStack(path: $agentsPath) {
                    SessionsListView(path: $agentsPath, showSettings: $showSettings)
                        .navigationDestination(for: UUID.self) { sessionId in
                            TerminalScreen(sessionId: sessionId)
                        }
                }
                .opacity(selectedTab == .agents ? 1 : 0)
                .allowsHitTesting(selectedTab == .agents)

                NavigationStack(path: $chatPath) {
                    ChatListView(path: $chatPath)
                        .navigationDestination(for: UUID.self) { id in
                            if let conv = chatStore.conversations.first(where: { $0.id == id }) {
                                ChatDetailView(conversationId: id, initialModel: conv.modelId)
                            }
                        }
                }
                .opacity(selectedTab == .chats ? 1 : 0)
                .allowsHitTesting(selectedTab == .chats)
            }
            // Leave room so list content scrolls above the bottom bar
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: isInsideSession ? 0 : 90)
            }

            // Bottom bar: left glass-pill tabs + right compose FAB.
            // Hidden when inside a terminal session (full-screen terminal).
            if isInsideSession == false {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: isInsideSession)
        .ignoresSafeArea(edges: .bottom)
    }

    // Hide bottom bar when inside a terminal session OR inside a chat detail.
    private var isInsideSession: Bool { !agentsPath.isEmpty || !chatPath.isEmpty }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        // GlassEffectContainer: both the tab pill and compose FAB share one
        // glass sampling region on iOS 26 (glass cannot sample other glass).
        GlassEffectContainerIfAvailable {
            HStack(alignment: .center, spacing: 0) {
                tabPill
                Spacer()
                composeFAB
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }

    // Left-aligned glass capsule containing the tab buttons
    private var tabPill: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                tabPillButton(tab)
            }
        }
        .padding(5)
        // liquidGlassCapsule() uses .glassEffect(.regular, in: .capsule) on iOS 26;
        // falls back to ultraThinMaterial capsule on older OS.
        .liquidGlassCapsule()
    }

    @ViewBuilder
    private func tabPillButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedTab = tab
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: isSelected ? 7 : 0) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
                if isSelected {
                    Text(tab.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                }
            }
            .padding(.horizontal, isSelected ? 18 : 14)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    // White inner pill — the Liquid Glass active-tab indicator
                    Capsule()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
    }

    // Floating compose FAB — context-aware:
    //   Agents tab → opens agent task compose sheet
    //   Chats tab  → creates a new chat conversation and navigates into it
    private var composeFAB: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            switch selectedTab {
            case .agents:
                showCompose = true
            case .chats:
                let model = chatStore.conversations.first?.modelId
                    ?? "gpt-4o-mini"
                let id = chatStore.newConversation(model: model)
                chatPath.append(id)
            }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassInteractiveCircle()
    }
}

// MARK: - Terminal screen (Chat | Files | Diff)

struct TerminalScreen: View {
    let sessionId: UUID
    @Environment(SessionStore.self) var store
    @Environment(AgentSessionStore.self) var agentStore
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionHistory.self) var sessionHistory
    @Environment(AppSettings.self) var settings
    @Environment(ProjectIndexModel.self) var projectIndex
    @Environment(GitStatusModel.self) var gitStatus
    @Environment(\.dismiss) var dismiss

    @State private var terminalVC = TerminalViewController()
    @State private var selectedTab: Tab = .chat
    /// For agent sessions: true = AgentChatView, false = terminal. Nil = PTY session (no toggle).
    @State private var agentChatMode: Bool? = nil

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
                case .chat:  primaryTab
                case .files: FileExplorerView(rootPath: cwd, onInsertReference: insertReference)
                case .diff:  GitDiffView(repoPath: cwd)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Mode toggle: only for agent sessions
            if agentChatMode != nil {
                ToolbarItem(placement: .topBarLeading) {
                    modePill
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    connection.send(.closeSession(sessionId: sessionId))
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                }
                .tint(Theme.danger)
            }
        }
        .onAppear {
            store.activeSessionId = sessionId
            // Initialise agentChatMode from the session's recorded mode
            if let info = store.sessions.first(where: { $0.id == sessionId }),
               info.agentProvider != nil {
                agentChatMode = (info.sessionMode ?? .chat) == .chat
            }
        }
        .onChange(of: store.sessions) { _, newValue in
            if !newValue.contains(where: { $0.id == sessionId }) {
                dismiss()
                return
            }
            // Reconcile local mode with server state if agentChatMode is being tracked
            if agentChatMode != nil,
               let info = newValue.first(where: { $0.id == sessionId }),
               let serverMode = info.sessionMode {
                let serverChat = serverMode == .chat
                if agentChatMode != serverChat { agentChatMode = serverChat }
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

    // MARK: - Primary (first) tab content

    @ViewBuilder
    private var primaryTab: some View {
        if agentChatMode == true {
            AgentChatView(sessionId: sessionId)
        } else {
            terminalTab
        }
    }

    private var terminalTab: some View {
        VStack(spacing: 0) {
            TerminalContainerView(sessionId: sessionId, terminalVC: terminalVC)
                .ignoresSafeArea(.keyboard)
            InputToolbar(terminalVC: terminalVC)
        }
    }

    // MARK: - Mode toggle pill (toolbar leading)

    private var modePill: some View {
        HStack(spacing: 0) {
            modeButton(label: "Chat", icon: "bubble.left.and.bubble.right.fill", active: agentChatMode == true) {
                switchMode(to: true)
            }
            modeButton(label: "Terminal", icon: "terminal.fill", active: agentChatMode == false) {
                switchMode(to: false)
            }
        }
        .padding(3)
        .background(Theme.surfaceHi, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
    }

    private func modeButton(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(active ? Color.black : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if active { Capsule().fill(Color.white) }
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: active)
    }

    private func switchMode(to chat: Bool) {
        guard agentChatMode != chat else { return }
        agentChatMode = chat
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        connection.send(.switchSessionMode(
            sessionId: sessionId,
            mode: chat ? .chat : .terminal
        ))
    }

    // MARK: - Helpers

    private var cwd: String {
        if let live = store.sessionCwds[sessionId], !live.isEmpty { return live }
        if let recorded = sessionHistory.entry(named: sessionName)?.cwd, !recorded.isEmpty { return recorded }
        let last = settings.lastWorkingDir
        return last.isEmpty ? "~" : last
    }

    private var sessionName: String {
        store.sessions.first(where: { $0.id == sessionId })?.name ?? "Session"
    }

    private func insertReference(_ relativePath: String) {
        terminalVC.injectText("@\(relativePath) ")
        selectedTab = .chat
    }
}
