// client/Sources/Features/Settings/SettingsSheet.swift
import SwiftUI

struct SettingsSheet: View {
    @Environment(AppSettings.self) var settings
    @Environment(ThemeStore.self) var themeStore
    @Environment(ConnectionManager.self) var connection
    @Environment(ConnectionHistory.self) var connectionHistory
    @Environment(\.dismiss) var dismiss
    @State private var draftKey: String = ""
    @State private var serverEditor: ServerEditState? = nil
    @State private var renamingEntry: SavedHost? = nil
    @State private var renameDraft: String = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        serverSection
                        agentsSection
                        themeSection
                        voiceSection
                        aboutSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tint(Theme.accent)
                }
            }
            .onAppear { draftKey = settings.deepgramAPIKey }
            .sheet(item: $serverEditor) { state in
                ServerEditorSheet(state: state) { saved in
                    save(serverEdit: saved)
                }
            }
            .alert("Rename Server", isPresented: renameBinding, presenting: renamingEntry) { entry in
                TextField("Name", text: $renameDraft)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    connectionHistory.rename(entry, to: renameDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    renamingEntry = nil
                }
                Button("Cancel", role: .cancel) { renamingEntry = nil }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renamingEntry != nil }, set: { if !$0 { renamingEntry = nil } })
    }

    private func save(serverEdit: ServerEditState) {
        let trimmedHost = serverEdit.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }
        let port = Int(serverEdit.port) ?? 8765
        let name = serverEdit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = serverEdit.token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = serverEdit.existing {
            var updated = existing
            updated.name = name
            updated.host = trimmedHost
            updated.port = port
            updated.token = token.isEmpty ? nil : token
            connectionHistory.upsert(updated)
        } else {
            let new = SavedHost(name: name, host: trimmedHost, port: port, token: token.isEmpty ? nil : token)
            connectionHistory.upsert(new)
        }
        serverEditor = nil
    }

    // MARK: - Sections

    private var serverSection: some View {
        sectionContainer(
            title: "Servers",
            subtitle: "Manage the Macs you connect to. Tap one to switch, long-press to rename."
        ) {
            VStack(spacing: 10) {
                // Current connection summary
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(connection.state == .connected ? Theme.success.opacity(0.18) : Theme.danger.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: connection.state == .connected ? "wifi" : "wifi.slash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(connection.state == .connected ? Theme.success : Theme.danger)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentHostDisplay)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(connection.state == .connected ? "Connected" : "Disconnected")
                            .font(.system(size: 11))
                            .foregroundStyle(connection.state == .connected ? Theme.success : Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        connection.disconnect()
                        dismiss()
                    } label: {
                        Text("Switch")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.06)))
                            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 0.5))

                ForEach(connectionHistory.sortedByRecency) { entry in
                    ServerRow(entry: entry,
                              isCurrent: entry.host == (UserDefaults.standard.string(forKey: "lastHost") ?? ""),
                              onTap: {
                                  // Switch to this server.
                                  connection.disconnect()
                                  UserDefaults.standard.set(entry.host, forKey: "lastHost")
                                  UserDefaults.standard.set(entry.port, forKey: "lastPort")
                                  connection.connect(host: entry.host, port: entry.port, token: entry.token ?? "")
                                  dismiss()
                              },
                              onEdit: {
                                  serverEditor = ServerEditState(
                                      id: entry.id,
                                      existing: entry,
                                      name: entry.name,
                                      host: entry.host,
                                      port: String(entry.port),
                                      token: entry.token ?? ""
                                  )
                              },
                              onRename: {
                                  renameDraft = entry.displayName
                                  renamingEntry = entry
                              },
                              onRemove: { connectionHistory.remove(entry) })
                }

                Button {
                    serverEditor = ServerEditState(
                        id: UUID(),
                        existing: nil,
                        name: "",
                        host: "",
                        port: "8765",
                        token: ""
                    )
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Add Server")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.10)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 0.7, dash: [4])))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentHostDisplay: String {
        let host = UserDefaults.standard.string(forKey: "lastHost") ?? "—"
        let port = UserDefaults.standard.integer(forKey: "lastPort")
        if host == "—" { return "—" }
        return port == 0 ? host : "\(host):\(port)"
    }

    private var agentsSection: some View {
        @Bindable var settings = settings
        return sectionContainer(
            title: "Agent CLIs",
            subtitle: "Override the binary each agent runs. Leave blank to use the default."
        ) {
            VStack(spacing: 12) {
                ForEach(CodingAgent.allCases) { agent in
                    AgentBinaryRow(
                        agent: agent,
                        defaultBinary: agent.defaultBinary,
                        value: Binding(
                            get: { settings.binary(for: agent) == agent.defaultBinary ? "" : settings.binary(for: agent) },
                            set: { settings.setBinary($0, for: agent) }
                        )
                    )
                }
            }
        }
    }

    private var themeSection: some View {
        sectionContainer(title: "Terminal Theme", subtitle: "Affects only the terminal colors. UI chrome stays monochrome.") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(themeStore.themes) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: theme.id == themeStore.current.id,
                        onSelect: { themeStore.select(theme) }
                    )
                }
            }
        }
    }

    private var voiceSection: some View {
        @Bindable var settings = settings
        return sectionContainer(
            title: "Voice Input",
            subtitle: "Maverick uses Deepgram to transcribe speech into terminal input. Get an API key at deepgram.com."
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Deepgram API Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                SecureField("dg_xxx…", text: $draftKey)
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                HStack {
                    Button("Save") {
                        settings.deepgramAPIKey = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if settings.hasDeepgramKey {
                        Button(role: .destructive) {
                            settings.deepgramAPIKey = ""
                            draftKey = ""
                        } label: {
                            Text("Clear")
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    if settings.hasDeepgramKey {
                        Label("Configured", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.success)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        sectionContainer(title: "About") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Maverick is a mobile companion for your Mac terminal.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text("All connections go through Tailscale; no data passes through our servers.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func sectionContainer<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 4)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                )
        }
    }
}

fileprivate struct ServerEditState: Identifiable {
    let id: UUID
    let existing: SavedHost?
    var name: String
    var host: String
    var port: String
    var token: String
}

private struct ServerRow: View {
    let entry: SavedHost
    let isCurrent: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.05)).frame(width: 32, height: 32)
                Image(systemName: "server.rack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.success : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(entry.host):\(entry.port)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 0.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(action: onTap) {
                Label("Connect", systemImage: "wifi")
            }
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive, action: onRemove) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct ServerEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var state: ServerEditState
    let onSave: (ServerEditState) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        field(label: "Name", icon: "tag.fill", placeholder: "e.g. Home Mac", text: $state.name)
                        field(label: "Host", icon: "network", placeholder: "100.x.x.x or hostname.ts.net", text: $state.host, mono: true, keyboard: .URL)
                        field(label: "Port", icon: "number", placeholder: "8765", text: $state.port, mono: true, keyboard: .numberPad)
                        field(label: "Token", icon: "key.fill", placeholder: "shared secret if configured", text: $state.token, secure: true)

                        Button { onSave(state) } label: {
                            Text(state.existing == nil ? "Add Server" : "Save Changes")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.onAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Capsule().fill(Theme.accent))
                        }
                        .disabled(state.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(state.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                        .buttonStyle(.plain)
                        .padding(.top, 6)
                    }
                    .padding(20)
                }
            }
            .navigationTitle(state.existing == nil ? "New Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.textSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func field(
        label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        mono: Bool = false,
        secure: Bool = false,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(label).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            Group {
                if secure { SecureField(placeholder, text: text) }
                else { TextField(placeholder, text: text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled() }
            }
            .font(.system(size: 15, weight: mono ? .medium : .regular, design: mono ? .monospaced : .default))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
    }
}

private struct AgentBinaryRow: View {
    let agent: CodingAgent
    let defaultBinary: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AgentIcon(agent: agent, size: 22)
                Text(agent.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !value.isEmpty {
                    Text("custom")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.4), lineWidth: 0.5))
                }
            }
            TextField(defaultBinary, text: $value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .padding(.vertical, 4)
    }
}

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                // Mini terminal preview
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: theme.terminal.background))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            Text("$")
                                .foregroundStyle(Color(hex: theme.terminal.green))
                            Text("ls -la")
                                .foregroundStyle(Color(hex: theme.terminal.foreground))
                        }
                        HStack(spacing: 0) {
                            Text("drwxr-xr-x ")
                                .foregroundStyle(Color(hex: theme.terminal.blue))
                            Text("project")
                                .foregroundStyle(Color(hex: theme.terminal.cyan))
                        }
                        Text("README.md")
                            .foregroundStyle(Color(hex: theme.terminal.yellow))
                    }
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .padding(8)
                }
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Theme.accent : Theme.stroke, lineWidth: isSelected ? 2 : 0.5)
                )

                HStack {
                    Text(theme.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.system(size: 13))
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
