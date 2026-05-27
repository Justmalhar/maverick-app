// client/Sources/Features/Sessions/SessionsListView.swift
import SwiftUI
import MaverickProtocol

struct SessionsListView: View {
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionHistory.self) var history
    @Environment(TaskLauncher.self) var launcher
    @Environment(AppSettings.self) var settings

    @Binding var path: NavigationPath
    @Binding var showSettings: Bool

    @State private var showNewSession = false
    @State private var newName = ""
    @State private var newCwd = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            content
            floatingActionButton
        }
        .toolbar(.hidden, for: .navigationBar)
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
    }

    // MARK: - Pieces

    private var background: some View {
        Theme.bg.ignoresSafeArea()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                TaskComposerCard()
                activeSection
                previousSection
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: launcher.launchedSessionId) { _, newValue in
            guard let newValue else { return }
            path.append(newValue)
            DispatchQueue.main.async { launcher.launchedSessionId = nil }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sessions")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var activeSection: some View {
        Section(header: sectionHeader(
            title: "Active",
            count: store.sessions.count,
            iconName: "circle.fill",
            iconColor: Theme.success
        )) {
            if store.sessions.isEmpty {
                emptyHint(text: "No sessions running. Tap + to start one.")
            } else {
                VStack(spacing: 8) {
                    ForEach(store.sessions) { session in
                        ActiveRow(session: session) {
                            store.activeSessionId = session.id
                            path.append(session.id)
                        } onClose: {
                            connection.send(.closeSession(sessionId: session.id))
                        }
                    }
                }
            }
        }
    }

    private var previousSection: some View {
        let activeNames = Set(store.sessions.map(\.name))
        let prev = history.previous(excluding: activeNames)
        return Group {
            if !prev.isEmpty {
                Section(header: sectionHeader(
                    title: "Previous",
                    count: prev.count,
                    iconName: "clock.fill",
                    iconColor: Theme.textTertiary
                )) {
                    VStack(spacing: 8) {
                        ForEach(prev) { entry in
                            PreviousRow(entry: entry) {
                                resume(entry: entry)
                            } onRemove: {
                                history.remove(entry)
                            }
                        }
                    }
                }
            }
        }
    }

    private var floatingActionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            newName = ""
            newCwd = settings.lastWorkingDir
            showNewSession = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Theme.accent))
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 24)
    }

    private func sectionHeader(title: String, count: Int, iconName: String, iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 8))
                .foregroundStyle(iconColor)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.8)
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func emptyHint(text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
                .opacity(0.6)
        )
    }

    /// `cwd` is taken from the alert's folder field; if blank, the server
    /// falls back to $HOME.
    private func create(name: String, cwd: String = "") {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwdOpt: String? = trimmedCwd.isEmpty ? nil : trimmedCwd
        if !trimmedCwd.isEmpty { settings.lastWorkingDir = trimmedCwd }
        connection.send(.createSession(name: trimmedName, shell: "/bin/zsh", cwd: cwdOpt))
        newName = ""
        newCwd = ""
    }

    /// Re-open a previous session. If the entry has an agent recorded, launch
    /// that agent with its resume flag (`claude -c`, etc.) so the prior
    /// conversation rehydrates from the agent's on-disk session store.
    /// Otherwise this falls back to creating a plain shell session.
    private func resume(entry: PastSession) {
        let cwdOpt: String? = entry.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyOrNil ?? settings.lastWorkingDir.nonEmptyOrNil

        guard let agentId = entry.agentId,
              let agent = CodingAgent(rawValue: agentId) else {
            // No agent recorded — just open a shell with the same name.
            connection.send(.createSession(name: entry.name, shell: "/bin/zsh", cwd: cwdOpt))
            return
        }

        let binary = settings.binary(for: agent)
        launcher.enqueue(
            sessionName: entry.name,
            binary: binary,
            task: nil,
            agent: agent,
            cwd: cwdOpt,
            resume: true
        )
        connection.send(.createSession(name: entry.name, shell: "/bin/zsh", cwd: cwdOpt))
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - Rows

private struct ActiveRow: View {
    let session: SessionInfo
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Live indicator
            ZStack {
                Circle().fill(Theme.success.opacity(0.18)).frame(width: 28, height: 28)
                Circle().fill(Theme.success).frame(width: 9, height: 9)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("Started \(session.createdAt, format: .relative(presentation: .named))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .contentShape(Rectangle())
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
        )
        .onTapGesture(perform: onOpen)
        .swipeActions(edge: .trailing) {
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
}

private struct PreviousRow: View {
    let entry: PastSession
    let onReopen: () -> Void
    let onRemove: () -> Void

    private var agent: CodingAgent? {
        guard let id = entry.agentId else { return nil }
        return CodingAgent(rawValue: id)
    }

    private var relativeWhen: String {
        let date = entry.closedAt ?? entry.lastSeen
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Closed \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private var subtitle: String {
        guard let cwd = entry.cwd, !cwd.isEmpty else { return relativeWhen }
        return "\(cwd)  •  \(relativeWhen)"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.04)).frame(width: 28, height: 28)
                if let agent {
                    AgentIcon(agent: agent, size: 16)
                } else {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()
            Text(agent != nil ? "Resume" : "Re-open")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
        )
        .onTapGesture(perform: onReopen)
        .contextMenu {
            Button(action: onReopen) {
                Label("Re-open", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Remove from history", systemImage: "trash")
            }
        }
    }
}
