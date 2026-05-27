// client/Sources/Features/Tasks/TaskComposerCard.swift
import SwiftUI

struct TaskComposerCard: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(TaskLauncher.self) var launcher
    @Environment(AppSettings.self) var settings

    @State private var task: String = ""
    @State private var agent: CodingAgent = .claudeCode
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
            Text(settings.binary(for: agent))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.04)))
                .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
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
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Run")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
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
        let trimmedTask = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTask.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let sessionName = sessionName(for: trimmedTask)
        let binary = settings.binary(for: agent)
        launcher.enqueue(sessionName: sessionName, binary: binary, task: trimmedTask)
        connection.send(.createSession(name: sessionName, shell: "/bin/zsh"))

        task = ""
        focused = false
    }

    private func sessionName(for task: String) -> String {
        let snippet = String(task.prefix(28)).trimmingCharacters(in: .whitespacesAndNewlines)
        return snippet.isEmpty ? agent.rawValue : "\(agent.rawValue) — \(snippet)"
    }
}

/// Renders a vector agent icon from `Agents.xcassets`. Falls back to a generic
/// SF Symbol if the asset isn't found.
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
