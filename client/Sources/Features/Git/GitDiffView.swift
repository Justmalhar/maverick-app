// client/Sources/Features/Git/GitDiffView.swift
import SwiftUI
import MaverickProtocol

/// Git diff tab inside a connected session. Renders `git status` for the
/// session's cwd as two collapsible groups (Staged / Working Tree) and
/// lazily fetches per-file diffs when a row is tapped.
struct GitDiffView: View {
    let repoPath: String

    @Environment(GitStatusModel.self) private var gitStatus
    @Environment(ConnectionManager.self) private var connection

    /// Diff-key set (GitStatusModel.key(file:staged:)) of rows currently expanded.
    @State private var expanded: Set<String> = []
    @State private var showStaged: Bool = true
    @State private var showUnstaged: Bool = true

    private static let maxVisibleDiffLines = 500

    var body: some View {
        Group {
            switch gitStatus.state {
            case .idle, .loading:
                loadingState
            case .error(let msg):
                errorState(msg)
            case .loaded:
                if gitStatus.status.isRepo {
                    loadedState
                } else {
                    notARepoState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            if gitStatus.path != repoPath {
                gitStatus.refresh(path: repoPath, connection: connection)
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView().tint(Theme.accent)
            Text("Loading status…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.danger)
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                gitStatus.refresh(path: repoPath, connection: connection)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Retry")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .liquidGlassCapsule()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var notARepoState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
            Text("Not a git repository")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(repoPath)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadedState: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Theme.stroke).frame(height: 0.5)
            if gitStatus.status.files.isEmpty {
                cleanState
            } else {
                fileList
            }
        }
    }

    private var cleanState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Theme.success)
            Text("Working tree clean")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let branch = gitStatus.status.branch {
                Text("on \(branch)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Header (branch chip + ahead/behind + refresh)

    private var header: some View {
        HStack(spacing: 8) {
            branchChip
            if gitStatus.status.ahead > 0 {
                aheadBehindPill(symbol: "arrow.up", count: gitStatus.status.ahead)
            }
            if gitStatus.status.behind > 0 {
                aheadBehindPill(symbol: "arrow.down", count: gitStatus.status.behind)
            }
            Spacer()
            refreshButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var branchChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(gitStatus.status.branch ?? "(detached)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassCapsule()
    }

    private func aheadBehindPill(symbol: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .liquidGlassCapsule()
    }

    private var refreshButton: some View {
        Button {
            gitStatus.refresh(path: repoPath, connection: connection)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .liquidGlassCircle()
        .disabled(gitStatus.state == .loading)
        .opacity(gitStatus.state == .loading ? 0.55 : 1)
    }

    // MARK: - File list

    private var stagedFiles: [GitFileStatus] {
        gitStatus.status.files.filter { $0.staged }
    }

    private var unstagedFiles: [GitFileStatus] {
        // Working tree includes both modified+untracked.
        gitStatus.status.files.filter { !$0.staged }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: []) {
                if !stagedFiles.isEmpty {
                    section(title: "Staged",
                            count: stagedFiles.count,
                            expanded: $showStaged,
                            files: stagedFiles)
                }
                if !unstagedFiles.isEmpty {
                    section(title: "Working Tree",
                            count: unstagedFiles.count,
                            expanded: $showUnstaged,
                            files: unstagedFiles)
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func section(title: String,
                         count: Int,
                         expanded: Binding<Bool>,
                         files: [GitFileStatus]) -> some View {
        VStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 10)
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.textSecondary)
                    countBadge(count)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.wrappedValue {
                VStack(spacing: 6) {
                    ForEach(files) { file in
                        fileRow(file)
                    }
                }
            }
        }
    }

    private func countBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Theme.surfaceHi)
            )
            .overlay(
                Capsule().stroke(Theme.stroke, lineWidth: 0.5)
            )
    }

    // MARK: - File row + inline diff

    private func fileRow(_ file: GitFileStatus) -> some View {
        let key = GitStatusModel.key(file: file.path, staged: file.staged)
        let isExpanded = expanded.contains(key)

        return VStack(spacing: 0) {
            Button {
                toggleRow(file: file, key: key)
            } label: {
                HStack(spacing: 10) {
                    statusChip(file.status)
                    Text(file.path)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                diffArea(file: file, key: key)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
    }

    private func toggleRow(file: GitFileStatus, key: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if expanded.contains(key) {
                expanded.remove(key)
            } else {
                expanded.insert(key)
                // Fetch lazily if we haven't already.
                if gitStatus.diffs[key] == nil {
                    gitStatus.fetchDiff(file: file.path,
                                        staged: file.staged,
                                        connection: connection)
                }
            }
        }
    }

    @ViewBuilder
    private func diffArea(file: GitFileStatus, key: String) -> some View {
        if let result = gitStatus.diffs[key] {
            renderDiff(text: result.text, truncated: result.truncated, status: file.status)
        } else if gitStatus.pendingDiffs.contains(key) {
            HStack(spacing: 8) {
                ProgressView().tint(Theme.accent).scaleEffect(0.8)
                Text("Loading diff…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else {
            // Edge case: expanded but no result and no in-flight request (e.g. failed silently).
            Text("No diff available.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func renderDiff(text: String, truncated: Bool, status: String) -> some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let visible = Array(lines.prefix(Self.maxVisibleDiffLines))
        let didTruncateInUI = lines.count > Self.maxVisibleDiffLines

        VStack(alignment: .leading, spacing: 0) {
            if visible.isEmpty || (visible.count == 1 && visible[0].isEmpty) {
                Text(emptyDiffMessage(for: status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 6)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(visible.enumerated()), id: \.offset) { _, line in
                            diffLine(line)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if didTruncateInUI {
                Text("Diff truncated at \(Self.maxVisibleDiffLines) lines for display.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            if truncated {
                Text("Diff truncated (256KB cap)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 0)
    }

    private func emptyDiffMessage(for status: String) -> String {
        switch status {
        case "?": return "Untracked file. No diff available — content not yet tracked by git."
        case "D": return "File deleted."
        default:  return "No diff content."
        }
    }

    @ViewBuilder
    private func diffLine(_ raw: String) -> some View {
        let (color, display) = colorize(line: raw)
        Text(display.isEmpty ? " " : display)
            .font(diffFont)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var diffFont: Font {
        // Prefer MesloLGS NF if available; otherwise system mono.
        if UIFont(name: "MesloLGS NF", size: 12) != nil {
            return Font.custom("MesloLGS NF", size: 12)
        }
        return Font.system(size: 12, weight: .medium, design: .monospaced)
    }

    /// Returns (color, displayString). Hunk-header indent is stripped.
    private func colorize(line: String) -> (Color, String) {
        if line.hasPrefix("@@") {
            // Strip any leading whitespace for hunk headers.
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            return (Color(hex: "#22d3ee"), String(trimmed))
        }
        // Treat `+++`/`---` file headers as muted to avoid mass-red coloring.
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return (Theme.textTertiary, line)
        }
        if line.hasPrefix("+") {
            return (Theme.success, line)
        }
        if line.hasPrefix("-") {
            return (Theme.danger, line)
        }
        if line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return (Theme.textTertiary, line)
        }
        return (Theme.textSecondary, line)
    }

    // MARK: - Status chip

    private func statusChip(_ status: String) -> some View {
        Text(status)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(statusColor(status))
            )
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "M": return Color(hex: "#60a5fa")
        case "A": return Theme.success
        case "D": return Theme.danger
        case "R": return Color(hex: "#fbbf24")
        case "C": return Color(hex: "#22d3ee")
        case "?": return Theme.textTertiary
        case "U": return Theme.danger
        default:  return Theme.textTertiary
        }
    }
}
