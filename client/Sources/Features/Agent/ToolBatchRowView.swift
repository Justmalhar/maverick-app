// client/Sources/Features/Agent/ToolBatchRowView.swift
import SwiftUI
import MaverickProtocol

// MARK: - ToolKind display metadata

extension ToolKind {
    var systemImage: String {
        switch self {
        case .read:               return "doc.text"
        case .write:              return "pencil.and.list.clipboard"
        case .edit:               return "square.and.pencil"
        case .notebookEdit:       return "note.text"
        case .glob:               return "folder.badge.magnifyingglass"
        case .grep:               return "magnifyingglass"
        case .lsp:                return "curlybraces"
        case .bash, .powerShell:  return "terminal"
        case .monitor:            return "eye"
        case .webFetch:           return "globe"
        case .webSearch:          return "magnifyingglass.circle"
        case .agent, .skill, .sendMessage: return "cpu"
        case .taskCreate, .taskUpdate, .taskGet, .taskList, .taskStop: return "checklist"
        case .cronCreate, .cronDelete, .cronList: return "clock"
        case .enterPlanMode, .exitPlanMode: return "list.bullet.clipboard"
        case .askUserQuestion:    return "questionmark.bubble"
        case .enterWorktree, .exitWorktree: return "arrow.triangle.branch"
        case .listMcpResources, .readMcpResource, .waitForMcpServers, .toolSearch: return "puzzlepiece.extension"
        case .pushNotification, .scheduleWakeup, .remoteTrigger, .shareOnboardingGuide: return "bell"
        case .custom:             return "wrench.and.screwdriver"
        }
    }

    var tintColor: Color {
        switch self {
        case .read, .write, .edit, .notebookEdit:              return Color(hex: "#60a5fa")
        case .glob, .grep, .lsp:                               return Color(hex: "#a78bfa")
        case .bash, .powerShell, .monitor:                     return Color(hex: "#fb923c")
        case .webFetch, .webSearch:                            return Color(hex: "#2dd4bf")
        case .agent, .skill, .sendMessage:                     return Color(hex: "#4ade80")
        case .taskCreate, .taskUpdate, .taskGet, .taskList, .taskStop,
             .cronCreate, .cronDelete, .cronList:              return Color(hex: "#facc15")
        case .enterPlanMode, .exitPlanMode, .askUserQuestion:  return Color(hex: "#94a3b8")
        case .enterWorktree, .exitWorktree:                    return Color(hex: "#f87171")
        case .listMcpResources, .readMcpResource,
             .waitForMcpServers, .toolSearch:                  return Color(hex: "#818cf8")
        case .pushNotification, .scheduleWakeup,
             .remoteTrigger, .shareOnboardingGuide:            return Color(hex: "#94a3b8")
        case .custom:                                          return Color(hex: "#94a3b8")
        }
    }

    var displayName: String {
        switch self {
        case .read:             return "Read"
        case .write:            return "Write"
        case .edit:             return "Edit"
        case .notebookEdit:     return "Notebook"
        case .glob:             return "Glob"
        case .grep:             return "Grep"
        case .lsp:              return "LSP"
        case .bash:             return "Bash"
        case .powerShell:       return "PowerShell"
        case .monitor:          return "Monitor"
        case .webFetch:         return "Fetch"
        case .webSearch:        return "Search"
        case .agent:            return "Agent"
        case .skill:            return "Skill"
        case .sendMessage:      return "Message"
        case .taskCreate:       return "TaskCreate"
        case .taskUpdate:       return "TaskUpdate"
        case .taskGet:          return "TaskGet"
        case .taskList:         return "TaskList"
        case .taskStop:         return "TaskStop"
        case .cronCreate:       return "CronCreate"
        case .cronDelete:       return "CronDelete"
        case .cronList:         return "CronList"
        case .enterPlanMode:    return "Plan"
        case .exitPlanMode:     return "ExitPlan"
        case .askUserQuestion:  return "AskUser"
        case .enterWorktree:    return "Worktree"
        case .exitWorktree:     return "ExitWorktree"
        case .listMcpResources: return "MCP"
        case .readMcpResource:  return "MCPRead"
        case .waitForMcpServers:return "MCPWait"
        case .toolSearch:       return "ToolSearch"
        case .pushNotification: return "Notify"
        case .scheduleWakeup:   return "Schedule"
        case .remoteTrigger:    return "Trigger"
        case .shareOnboardingGuide: return "Share"
        case .custom(let n):    return n
        }
    }
}

// MARK: - File diff pills

struct FileDiffPillsView: View {
    let diffs: [FileDiff]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(diffs, id: \.path) { diff in
                HStack(spacing: 3) {
                    if diff.added > 0 {
                        Text("+\(diff.added)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.success)
                    }
                    if diff.removed > 0 {
                        Text("-\(diff.removed)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.danger)
                    }
                    Text(URL(fileURLWithPath: diff.path).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

// MARK: - Single tool call row

private struct ToolCallRow: View {
    let event: ToolCallEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: event.tool.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(event.tool.tintColor)
                    .frame(width: 18)

                Text(event.tool.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                if !event.inputSummary.isEmpty {
                    Text(event.inputSummary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)

                if let ms = event.durationMs {
                    Text(formatDuration(ms))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }

                statusIcon
            }

            if let diffs = event.fileDiffs, !diffs.isEmpty {
                FileDiffPillsView(diffs: diffs)
                    .padding(.leading, 24)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.bg.opacity(0.6))
    }

    @ViewBuilder private var statusIcon: some View {
        if event.error != nil {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.danger)
        } else if event.result != nil || event.durationMs != nil {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.success)
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }
}

// MARK: - Tool batch row

struct ToolBatchRowView: View {
    let tools: [ToolCallEvent]
    let initiallyCollapsed: Bool

    @State private var isCollapsed: Bool

    init(tools: [ToolCallEvent], initiallyCollapsed: Bool) {
        self.tools = tools
        self.initiallyCollapsed = initiallyCollapsed
        _isCollapsed = State(initialValue: initiallyCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !isCollapsed {
                Divider().overlay(Theme.stroke)
                expandedRows
            }
        }
        .background(Theme.surfaceHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.5)
        )
        .padding(.vertical, 3)
    }

    private var header: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { isCollapsed.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 12)
                    .animation(.snappy(duration: 0.2), value: isCollapsed)

                // Tool icon cluster (up to 3, matching the label prefix cap)
                HStack(spacing: -2) {
                    ForEach(Array(uniqueToolKinds.prefix(3).enumerated()), id: \.offset) { _, kind in
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 11))
                            .foregroundStyle(kind.tintColor)
                            .frame(width: 18, height: 18)
                            .background(Theme.surface, in: Circle())
                    }
                }

                Text(headerLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let totalMs = totalDuration {
                    Text(formatDuration(totalMs))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tools.enumerated()), id: \.element.id) { idx, tool in
                if idx > 0 {
                    Divider().overlay(Theme.stroke).padding(.leading, 12)
                }
                ToolCallRow(event: tool)
            }
        }
    }

    // MARK: - Helpers

    private var uniqueToolKinds: [ToolKind] {
        var seen: Set<String> = []
        return tools.compactMap { tool -> ToolKind? in
            let key = tool.tool.displayName
            if seen.contains(key) { return nil }
            seen.insert(key)
            return tool.tool
        }
    }

    private var headerLabel: String {
        if tools.count == 1 {
            let t = tools[0]
            let summary = t.inputSummary.isEmpty ? t.tool.displayName : t.inputSummary
            return summary.prefix(60).description
        }
        let names = uniqueToolKinds.prefix(3).map(\.displayName).joined(separator: ", ")
        let suffix = tools.count > 3 ? " +\(tools.count - 3)" : ""
        return names + suffix
    }

    private var totalDuration: Int? {
        let durations = tools.compactMap(\.durationMs)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    private func formatDuration(_ ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        return String(format: "%.1fs", Double(ms) / 1000)
    }
}

// MARK: - FlowLayout helper (wrapping HStack)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                y += rowH + spacing; x = 0; rowH = 0
            }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowH + spacing; x = bounds.minX; rowH = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
