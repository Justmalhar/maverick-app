// client/Sources/Features/Sessions/SessionsListView.swift
import SwiftUI
import MaverickProtocol

// MARK: - Main list view

struct SessionsListView: View {
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionHistory.self) var history
    @Environment(TaskLauncher.self) var launcher
    @Environment(AppSettings.self) var settings

    @Binding var path: NavigationPath
    @Binding var showSettings: Bool

    @State private var showCompose = false
    @State private var composeAgent: CodingAgent? = nil
    @State private var filterMode: FilterMode = .all
    @State private var showNewSession = false
    @State private var newName = ""
    @State private var newCwd = ""

    // Edit / multi-select state
    @State private var isEditing = false
    @State private var selectedSessionIds: Set<UUID> = []
    @State private var selectedHistoryIds: Set<UUID> = []

    private var selectedCount: Int { selectedSessionIds.count + selectedHistoryIds.count }

    enum FilterMode: CaseIterable {
        case all, active, previous
        var label: String {
            switch self {
            case .all:      return "All"
            case .active:   return "Active"
            case .previous: return "Previous"
            }
        }
        var icon: String {
            switch self {
            case .all:      return "bubble.left.and.bubble.right.fill"
            case .active:   return "circle.fill"
            case .previous: return "clock.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navigationHeader
                if !isEditing {
                    pinnedAgentsRow
                    sessionDivider
                }
                // sessionsList is a List, so it owns its own scrolling. We
                // intentionally do NOT wrap it in a ScrollView — that nesting
                // was eating the swipe gesture and disabling .swipeActions.
                sessionsList
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCompose) {
            ComposeSheetContent(initialAgent: composeAgent) { showCompose = false }
        }
        .alert("New Session", isPresented: $showNewSession) {
            TextField("Name (e.g. claude, build, logs)", text: $newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Folder (default: ~)", text: $newCwd)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Create") { create(name: newName, cwd: newCwd) }
            Button("Cancel", role: .cancel) { newName = ""; newCwd = "" }
        } message: {
            Text("A new /bin/zsh session will start on your Mac in the chosen folder.")
        }
        .onAppear { connection.send(.listSessions) }
        .onChange(of: launcher.launchedSessionId) { _, newValue in
            guard let newValue else { return }
            path.append(newValue)
            DispatchQueue.main.async { launcher.launchedSessionId = nil }
        }
    }

    // MARK: - Navigation header (transparent — blends with app background)

    private var navigationHeader: some View {
        HStack(spacing: 8) {
            if isEditing {
                // Edit mode: glass Cancel pill on left, glass Delete pill on right
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isEditing = false
                        selectedSessionIds = []
                        selectedHistoryIds = []
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule()
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Select Sessions")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()

                Button {
                    deleteSelected()
                } label: {
                    Text(selectedCount == 0 ? "Delete" : "Delete (\(selectedCount))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(selectedCount > 0 ? Theme.danger : Theme.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule()
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
            } else {
                // Normal mode: glass Edit pill, transparent title, glass filter circle
                Button {
                    withAnimation(.snappy(duration: 0.2)) { isEditing = true }
                } label: {
                    Text("Edit")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule() // real glassEffect on iOS 26
                }
                .buttonStyle(.plain)

                Spacer()
                Text("Agents")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()

                GlassEffectContainerIfAvailable {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassCircleButtonStyle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        // Transparent — matches the pure-black app background seamlessly
        .background(Color.clear)
    }

    // MARK: - Pinned agents row (center-aligned grid)

    // Agents shown in the pinned row — excludes Hermes (available via compose sheet).
    private let pinnedAgents: [CodingAgent] = CodingAgent.allCases.filter { $0 != .hermes }

    private var pinnedAgentsRow: some View {
        HStack(spacing: 0) {
            // "+" button — starts a plain /bin/zsh session with no agent
            PinnedTerminalButton {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                newName = ""
                newCwd = settings.lastWorkingDir
                showNewSession = true
            }
            .frame(maxWidth: .infinity)

            ForEach(pinnedAgents) { agent in
                PinnedAgentButton(agent: agent) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    composeAgent = agent
                    showCompose = true
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
    }

    private var sessionDivider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 0.5)
    }

    // MARK: - Sessions list

    /// `List` (not LazyVStack) so each row gets system-level `.swipeActions`
    /// support. Visual styling matches the rest of the app via .plain list
    /// style + transparent row backgrounds + zero insets + hidden separators
    /// — same pattern ChatListView uses.
    private var sessionsList: some View {
        let activeNames = Set(store.sessions.map(\.name))
        let prev = history.previous(excluding: activeNames)
        let showActive = filterMode != .previous
        let showPrev = filterMode != .active

        return Group {
            if store.sessions.isEmpty && prev.isEmpty {
                switch filterMode {
                case .all:
                    emptyState(icon: "bubble.left.and.bubble.right",
                               text: "No sessions yet",
                               hint: "Assign work to an agent above or tap ✏️")
                case .active:
                    emptyState(icon: "terminal", text: "No active sessions",
                               hint: "Tap an agent above or ✏️ to assign work")
                case .previous:
                    emptyState(icon: "clock", text: "No previous sessions",
                               hint: "Completed sessions will appear here")
                }
            } else {
                List {
                    if showActive {
                        ForEach(store.sessions) { session in
                            AgentSessionRow(
                                session: session,
                                isEditing: isEditing,
                                isSelected: selectedSessionIds.contains(session.id),
                                onTap: {
                                    if isEditing {
                                        toggleSession(session.id)
                                    } else {
                                        store.activeSessionId = session.id
                                        path.append(session.id)
                                    }
                                },
                                onClose: {
                                    connection.send(.closeSession(sessionId: session.id))
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                    if showPrev {
                        ForEach(prev) { entry in
                            PreviousAgentSessionRow(
                                entry: entry,
                                isEditing: isEditing,
                                isSelected: selectedHistoryIds.contains(entry.id),
                                onTap: {
                                    if isEditing {
                                        toggleHistory(entry.id)
                                    } else {
                                        resume(entry: entry)
                                    }
                                },
                                onRemove: { history.remove(entry) }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
            }
        }
    }

    private var insetDivider: some View {
        Rectangle()
            .fill(Theme.stroke.opacity(0.6))
            .frame(height: 0.5)
            .padding(.leading, 78)
    }

    private func emptyState(icon: String, text: String, hint: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 36)).foregroundStyle(Theme.textTertiary)
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text(hint).font(.system(size: 13)).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
        }
        .padding(48).frame(maxWidth: .infinity)
    }

    // MARK: - Edit / select helpers

    private func toggleSession(_ id: UUID) {
        if selectedSessionIds.contains(id) { selectedSessionIds.remove(id) }
        else { selectedSessionIds.insert(id) }
    }

    private func toggleHistory(_ id: UUID) {
        if selectedHistoryIds.contains(id) { selectedHistoryIds.remove(id) }
        else { selectedHistoryIds.insert(id) }
    }

    private func deleteSelected() {
        for id in selectedSessionIds {
            connection.send(.closeSession(sessionId: id))
        }
        let activeNames = Set(store.sessions.map(\.name))
        for entry in history.previous(excluding: activeNames) where selectedHistoryIds.contains(entry.id) {
            history.remove(entry)
        }
        withAnimation(.snappy(duration: 0.2)) {
            isEditing = false
            selectedSessionIds = []
            selectedHistoryIds = []
        }
    }

    // MARK: - Session actions

    private func create(name: String, cwd: String = "") {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwdOpt: String? = trimmedCwd.isEmpty ? nil : trimmedCwd
        if !trimmedCwd.isEmpty { settings.lastWorkingDir = trimmedCwd }
        connection.send(.createSession(name: trimmedName, shell: "/bin/zsh", cwd: cwdOpt))
        newName = ""; newCwd = ""
    }

    private func resume(entry: PastSession) {
        let cwdOpt: String? = entry.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyOrNil ?? settings.lastWorkingDir.nonEmptyOrNil
        guard let agentId = entry.agentId, let agent = CodingAgent(rawValue: agentId) else {
            connection.send(.createSession(name: entry.name, shell: "/bin/zsh", cwd: cwdOpt))
            return
        }
        let binary = settings.binary(for: agent)
        launcher.enqueue(sessionName: entry.name, binary: binary, task: nil, agent: agent, cwd: cwdOpt, resume: true)
        connection.send(.createSession(name: entry.name, shell: "/bin/zsh", cwd: cwdOpt))
    }
}

// MARK: - Pinned terminal button (plain shell, no agent)

private struct PinnedTerminalButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 58, height: 58)
                    .glassInteractiveCircle()
                Text("Terminal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pinned agent button (center-aligned, Liquid Glass circle)

private struct PinnedAgentButton: View {
    let agent: CodingAgent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                AgentIcon(agent: agent, size: 26, color: agent.accentColor)
                    .frame(width: 58, height: 58)
                    // iOS 26: real Liquid Glass with interactive bounce/shimmer on tap.
                    // iOS <26: frosted circle fallback.
                    .glassInteractiveCircle()
                Text(agent.shortName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Active session row

private struct AgentSessionRow: View {
    let session: SessionInfo
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    private var agent: CodingAgent? {
        CodingAgent.allCases.first { session.name.hasPrefix($0.rawValue) }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isEditing {
                    selectCircle(isSelected: isSelected)
                }

                agentAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("Active · started \(session.createdAt, format: .relative(presentation: .named))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onClose) {
                Label("Close", systemImage: "xmark.circle.fill")
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onClose) {
                Label("Close session", systemImage: "xmark.circle.fill")
            }
        }
    }

    /// Active sessions: provider icon in its native brand colors inside a
    /// tinted halo. The colored icon IS the 'live' signal.
    @ViewBuilder
    private var agentAvatar: some View {
        ZStack {
            Circle()
                .fill((agent?.accentColor ?? Theme.success).opacity(0.16))
                .frame(width: 42, height: 42)
            Circle()
                .strokeBorder((agent?.accentColor ?? Theme.success).opacity(0.45), lineWidth: 0.8)
                .frame(width: 42, height: 42)
            if let agent {
                // color: nil → render the SVG's native colors (brand).
                AgentIcon(agent: agent, size: 22)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.success)
            }
        }
    }
}

// MARK: - Previous session row

private struct PreviousAgentSessionRow: View {
    let entry: PastSession
    let isEditing: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    /// Prefer the recorded agentId; fall back to detecting the agent from the
    /// session name's prefix so older entries (which didn't record the agent)
    /// still get a provider icon.
    private var agent: CodingAgent? {
        if let id = entry.agentId, let a = CodingAgent(rawValue: id) { return a }
        return CodingAgent.allCases.first { entry.name.hasPrefix($0.rawValue) }
    }

    private var subtitle: String {
        let whenStr = relativeWhen
        guard let cwd = entry.cwd, !cwd.isEmpty else { return whenStr }
        let shortCwd = cwd.split(separator: "/").suffix(2).joined(separator: "/")
        return "\(shortCwd) · \(whenStr)"
    }

    private var relativeWhen: String {
        let date = entry.closedAt ?? entry.lastSeen
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if isEditing {
                    selectCircle(isSelected: isSelected)
                }

                agentAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                if !isEditing {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary.opacity(0.6))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(action: onTap) { Label("Re-open", systemImage: "arrow.counterclockwise") }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from history", systemImage: "trash")
            }
        }
    }

    /// Closed sessions: provider icon rendered with native brand colors but
    /// at reduced opacity inside a neutral halo. Brand still recognizable,
    /// but the dimming is the "this isn't running" signal.
    @ViewBuilder
    private var agentAvatar: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.04)).frame(width: 42, height: 42)
            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8).frame(width: 42, height: 42)
            if let agent {
                AgentIcon(agent: agent, size: 22)
                    .opacity(0.55)
                    .saturation(0.7)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - Shared select circle

private func selectCircle(isSelected: Bool) -> some View {
    ZStack {
        Circle()
            .strokeBorder(isSelected ? Theme.accent : Theme.textTertiary, lineWidth: 1.5)
            .frame(width: 22, height: 22)
        if isSelected {
            Circle().fill(Theme.accent).frame(width: 22, height: 22)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onAccent)
        }
    }
}

// MARK: - Compose sheet (internal — also used from ContentView's FAB)

struct ComposeSheetContent: View {
    let initialAgent: CodingAgent?
    let onDone: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TaskComposerCard(
                    initialAgent: initialAgent ?? .claudeCode,
                    onSubmit: { dismiss() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Helpers

private extension String {
    var nonEmptyOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
