// client/Sources/Features/Sessions/SessionTabBar.swift
import SwiftUI
import MaverickProtocol

struct SessionTabBar: View {
    @Environment(SessionStore.self) var store
    @Environment(ConnectionManager.self) var connection
    @State private var showNewSession = false
    @State private var newName = ""

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 8) {
            // Session pills
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(store.sessions) { session in
                            SessionChip(
                                session: session,
                                active: session.id == store.activeSessionId,
                                onTap: { store.activeSessionId = session.id },
                                onClose: { connection.send(.closeSession(sessionId: session.id)) }
                            )
                            .id(session.id)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: store.activeSessionId) { _, new in
                    guard let new else { return }
                    withAnimation(.snappy) { proxy.scrollTo(new, anchor: .center) }
                }
            }

            // New session button
            Button { showNewSession = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
            }
            .padding(.trailing, 10)
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
        .overlay(
            Rectangle().fill(Theme.stroke).frame(height: 0.5),
            alignment: .bottom
        )
        .alert("New Session", isPresented: $showNewSession) {
            TextField("e.g. claude, build, logs", text: $newName)
                .textInputAutocapitalization(.never)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                connection.send(.createSession(name: name, shell: "/bin/zsh"))
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("A new /bin/zsh session will be created on your Mac.")
        }
        .onAppear { connection.send(.listSessions) }
    }
}

private struct SessionChip: View {
    let session: SessionInfo
    let active: Bool
    let onTap: () -> Void
    let onClose: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(active ? Theme.accent : Theme.textSecondary)
                Text(session.name)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(3)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(active ? Theme.accent.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(active ? Theme.accent.opacity(0.7) : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
