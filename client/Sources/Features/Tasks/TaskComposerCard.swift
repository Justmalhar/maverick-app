// client/Sources/Features/Tasks/TaskComposerCard.swift
import SwiftUI

struct TaskComposerCard: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(TaskLauncher.self) var launcher

    @State private var task: String = ""
    @State private var agent: CodingAgent = .claudeCode
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            TextField(
                "Describe what you want the agent to do…",
                text: $task,
                axis: .vertical
            )
            .lineLimit(2...4)
            .focused($focused)
            .font(.system(size: 14))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 0.5)
            )

            HStack(spacing: 8) {
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
        }
    }

    private var agentPicker: some View {
        Menu {
            ForEach(CodingAgent.allCases) { candidate in
                Button {
                    agent = candidate
                } label: {
                    Label(candidate.rawValue, systemImage: candidate.iconName)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: agent.iconName)
                    .font(.system(size: 12, weight: .semibold))
                Text(agent.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .menuOrder(.fixed)
    }

    private var runButton: some View {
        Button(action: submit) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Run")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .opacity(isEmpty ? 0.45 : 1)
    }

    private var isEmpty: Bool {
        task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let sessionName = agent.sessionName(for: trimmed)
        let command = agent.command(for: trimmed)
        launcher.enqueue(sessionName: sessionName, command: command)
        connection.send(.createSession(name: sessionName, shell: "/bin/zsh"))

        task = ""
        focused = false
    }
}
