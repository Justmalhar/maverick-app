// client/Sources/Features/Explorer/FileExplorerView.swift
import SwiftUI
import MaverickProtocol

/// File-explorer tab inside a connected session. Streams a project index from
/// the server and renders it as a collapsible tree. Tapping a file injects an
/// `@<relative-path>` token into the terminal input (the host then switches
/// back to the Chat tab).
struct FileExplorerView: View {
    let rootPath: String
    let onInsertReference: (String) -> Void

    @Environment(ProjectIndexModel.self) private var projectIndex
    @Environment(ConnectionManager.self) private var connection

    /// Relative paths of directories the user has expanded. Empty string ("")
    /// represents the root directory and is expanded by default.
    @State private var expanded: Set<String> = [""]

    var body: some View {
        @Bindable var index = projectIndex
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)

                Text(prettyRoot)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Toggle("", isOn: $index.showHidden)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.accent)
                        .scaleEffect(0.7)
                    Text("Hidden")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassCapsule()

                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .liquidGlassCircle()
                .disabled(projectIndex.state == .loading)
                .opacity(projectIndex.state == .loading ? 0.55 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider().background(Theme.stroke).frame(height: 0.5)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            if projectIndex.root != rootPath {
                projectIndex.index(path: rootPath, refresh: false, connection: connection)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch projectIndex.state {
        case .idle:
            placeholder("Tap refresh to index this project.", symbol: "folder")
        case .loading where projectIndex.entries.isEmpty:
            VStack(spacing: 10) {
                Spacer()
                ProgressView().tint(Theme.accent)
                Text("Indexing…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            errorState(message: message)
        case .loading, .loaded:
            tree
        }
    }

    @ViewBuilder
    private var tree: some View {
        let rows = flatten()
        if rows.isEmpty && projectIndex.state == .loaded {
            placeholder("Empty project", symbol: "tray")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Streaming indicator while more entries arrive.
                    if projectIndex.state == .loading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.textSecondary)
                            Text("Indexing more…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }

                    // Root row (project directory).
                    rootRow

                    // Visible (depth-aware) flat list of entries.
                    ForEach(rows, id: \.entry.path) { row in
                        rowView(for: row.entry, depth: row.depth)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var rootRow: some View {
        let isExpanded = expanded.contains("")
        return Button {
            toggle("")
        } label: {
            HStack(spacing: 8) {
                chevron(isExpanded: isExpanded)
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .frame(width: 18)
                Text(rootDisplayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("\(projectIndex.entries.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle().fill(Theme.stroke).frame(height: 0.5),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func rowView(for entry: IndexEntry, depth: Int) -> some View {
        let indent = CGFloat(depth) * 14
        if entry.isDirectory {
            directoryRow(entry: entry, indent: indent)
        } else {
            fileRow(entry: entry, indent: indent)
        }
    }

    private func directoryRow(entry: IndexEntry, indent: CGFloat) -> some View {
        let isExpanded = expanded.contains(entry.path)
        return Button {
            toggle(entry.path)
        } label: {
            HStack(spacing: 8) {
                Spacer().frame(width: indent)
                chevron(isExpanded: isExpanded)
                Image(systemName: "folder.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .frame(width: 18)
                Text(displayName(of: entry))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle().fill(Theme.stroke).frame(height: 0.5),
            alignment: .bottom
        )
    }

    private func fileRow(entry: IndexEntry, indent: CGFloat) -> some View {
        Button {
            onInsertReference(entry.path)
        } label: {
            HStack(spacing: 8) {
                Spacer().frame(width: indent)
                // Invisible chevron slot for alignment with directory rows.
                Color.clear.frame(width: 12, height: 12)
                Image(systemName: "doc")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 18)
                Text(displayName(of: entry))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let size = entry.size {
                    Text(byteFormatter.string(fromByteCount: size))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(
            Rectangle().fill(Theme.stroke).frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - States

    private func placeholder(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                refresh()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Retry")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .liquidGlassCapsule()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tree flattening

    private struct Row {
        let entry: IndexEntry
        let depth: Int
    }

    /// Produces a depth-aware flat list of visible entries. The root is implied
    /// (rendered separately) at depth 0; its direct children render at depth 1.
    /// If the root collapse-toggle is closed, returns an empty list.
    private func flatten() -> [Row] {
        guard expanded.contains("") else { return [] }
        var rows: [Row] = []
        rows.reserveCapacity(projectIndex.entries.count)
        appendChildren(of: "", depth: 1, into: &rows)
        return rows
    }

    private func appendChildren(of parent: String, depth: Int, into rows: inout [Row]) {
        let kids = projectIndex.children(of: parent)
        for entry in kids {
            rows.append(Row(entry: entry, depth: depth))
            if entry.isDirectory && expanded.contains(entry.path) {
                appendChildren(of: entry.path, depth: depth + 1, into: &rows)
            }
        }
    }

    // MARK: - Helpers

    private func toggle(_ key: String) {
        withAnimation(.snappy(duration: 0.18)) {
            if expanded.contains(key) {
                expanded.remove(key)
            } else {
                expanded.insert(key)
            }
        }
    }

    private func refresh() {
        projectIndex.index(path: rootPath, refresh: true, connection: connection)
    }

    private func chevron(isExpanded: Bool) -> some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(.snappy(duration: 0.18), value: isExpanded)
    }

    private func displayName(of entry: IndexEntry) -> String {
        guard let last = entry.path.split(separator: "/").last else { return entry.path }
        return String(last)
    }

    private var rootDisplayName: String {
        let path = projectIndex.root.isEmpty ? rootPath : projectIndex.root
        let trimmed = path.hasSuffix("/") && path.count > 1
            ? String(path.dropLast())
            : path
        if let last = trimmed.split(separator: "/").last {
            return String(last)
        }
        return trimmed
    }

    /// Abbreviates the root path: `/Users/<name>/foo/bar` → `~/foo/bar`.
    /// Anything else just shows the last two path components.
    private var prettyRoot: String {
        let path = projectIndex.root.isEmpty ? rootPath : projectIndex.root
        if path.hasPrefix("/Users/") {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                let rest = parts.dropFirst(2)
                return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
            }
            return path
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count >= 2 {
            return ".../" + parts.suffix(2).joined(separator: "/")
        }
        return path
    }

    private var byteFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }
}
