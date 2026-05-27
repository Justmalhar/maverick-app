// client/Sources/Features/Sessions/SessionsListView.swift
import SwiftUI
import MaverickProtocol

struct SessionsListView: View {
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @Environment(SessionHistory.self) var history
    @Environment(TaskLauncher.self) var launcher

    @Binding var path: NavigationPath
    @Binding var showSettings: Bool

    @State private var showNewSession = false
    @State private var newName = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            background
            content
            floatingActionButton
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .tint(Theme.textSecondary)
            }
        }
        .alert("New Session", isPresented: $showNewSession) {
            TextField("e.g. claude, build, logs", text: $newName)
                .textInputAutocapitalization(.never)
            Button("Create") { create(name: newName) }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("A new /bin/zsh session will start on your Mac.")
        }
        .onAppear { connection.send(.listSessions) }
    }

    // MARK: - Pieces

    private var background: some View {
        Theme.bg.ignoresSafeArea()
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TaskComposerCard()
                activeSection
                previousSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: launcher.launchedSessionId) { _, newValue in
            guard let newValue else { return }
            path.append(newValue)
            // Reset so subsequent launches re-trigger.
            DispatchQueue.main.async { launcher.launchedSessionId = nil }
        }
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
                                create(name: entry.name)
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

    private func create(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        connection.send(.createSession(name: trimmed, shell: "/bin/zsh"))
        newName = ""
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.04)).frame(width: 28, height: 28)
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("Closed \(entry.closedAt ?? entry.lastSeen, format: .relative(presentation: .named))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()
            Text("Re-open")
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
