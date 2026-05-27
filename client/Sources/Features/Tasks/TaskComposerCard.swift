// client/Sources/Features/Tasks/TaskComposerCard.swift
import SwiftUI
import UniformTypeIdentifiers

struct TaskComposerCard: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(TaskLauncher.self) var launcher
    @Environment(AppSettings.self) var settings
    @Environment(AttachmentManager.self) var attachments

    @State private var task: String = ""
    @State private var agent: CodingAgent = .claudeCode
    @State private var showFilePicker = false
    @State private var lastError: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            // Bigger multi-line task input.
            TextField(
                "Describe what you want the agent to do…",
                text: $task,
                axis: .vertical
            )
            .lineLimit(5...10)
            .focused($focused)
            .font(.system(size: 15))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.stroke, lineWidth: focused ? 1 : 0.5)
            )

            if !attachments.attachments.isEmpty {
                attachmentChips
            }

            HStack(spacing: 8) {
                attachButton
                agentPicker
                Spacer()
                runButton
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
        )
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFilePick(result: result)
        }
        .alert("Attachment failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("New Task")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(settings.binary(for: agent))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments.attachments) { item in
                    AttachmentChip(attachment: item) {
                        attachments.remove(id: item.id)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var attachButton: some View {
        Button {
            showFilePicker = true
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private var agentPicker: some View {
        Menu {
            ForEach(CodingAgent.allCases) { candidate in
                Button {
                    agent = candidate
                } label: {
                    HStack {
                        Text(candidate.rawValue)
                        if candidate == agent {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                AgentIcon(agent: agent, size: 18)
                Text(agent.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .menuOrder(.fixed)
    }

    private var runButton: some View {
        Button(action: submit) {
            HStack(spacing: 6) {
                if attachments.anyUploading {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(attachments.anyUploading ? "Uploading…" : "Run")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .disabled(disableSubmit)
        .opacity(disableSubmit ? 0.45 : 1)
    }

    private var disableSubmit: Bool {
        if attachments.anyUploading { return true }
        // Must have either text or at least one ready attachment.
        let textEmpty = task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return textEmpty && attachments.readyPaths.isEmpty
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { lastError != nil }, set: { if !$0 { lastError = nil } })
    }

    // MARK: - Actions

    private func handleFilePick(result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            lastError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                let needsAccess = url.startAccessingSecurityScopedResource()
                defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    _ = try attachments.startUpload(
                        filename: url.lastPathComponent,
                        data: data,
                        connection: connection
                    )
                } catch {
                    lastError = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
                }
            }
        }
    }

    private func submit() {
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = attachments.readyPaths
        guard !trimmedTask.isEmpty || !paths.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Embed attachment paths so the agent sees them in the prompt.
        // Pattern is "@/abs/path" which Claude Code reads as a file reference
        // and other agents will at minimum see as literal text.
        let pathPrefix = paths.map { "@\($0)" }.joined(separator: " ")
        let body: String
        if pathPrefix.isEmpty {
            body = trimmedTask
        } else if trimmedTask.isEmpty {
            body = pathPrefix
        } else {
            body = "\(pathPrefix)\n\n\(trimmedTask)"
        }

        let name = sessionName(for: trimmedTask.isEmpty ? "attachments" : trimmedTask)
        let binary = settings.binary(for: agent)
        launcher.enqueue(sessionName: name, binary: binary, task: body)
        connection.send(.createSession(name: name, shell: "/bin/zsh"))

        task = ""
        attachments.clear()
        focused = false
    }

    private func sessionName(for task: String) -> String {
        let snippet = String(task.prefix(28)).trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? agent.rawValue : "\(agent.rawValue) — \(snippet)"
    }
}

// MARK: - Attachment chip

private struct AttachmentChip: View {
    let attachment: AttachmentManager.Attachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            statusIcon
            Text(attachment.filename)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(strokeColor, lineWidth: 0.5))
    }

    @ViewBuilder private var statusIcon: some View {
        switch attachment.status {
        case .uploading:
            ProgressView().scaleEffect(0.55).frame(width: 12, height: 12)
        case .ready:
            Image(systemName: "doc.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textPrimary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Theme.danger)
        }
    }

    private var textColor: Color {
        if case .failed = attachment.status { return Theme.danger }
        return Theme.textPrimary
    }
    private var strokeColor: Color {
        if case .failed = attachment.status { return Theme.danger.opacity(0.5) }
        return Theme.stroke
    }
}

// MARK: - Agent icon helper

struct AgentIcon: View {
    let agent: CodingAgent
    var size: CGFloat = 20

    var body: some View {
        if UIImage(named: agent.assetName) != nil {
            Image(agent.assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(Theme.textPrimary)
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.7))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: size, height: size)
        }
    }
}
