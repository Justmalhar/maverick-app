// client/Sources/Features/Folder/DirectoryBrowserSheet.swift
import SwiftUI
import MaverickProtocol

struct DirectoryBrowserSheet: View {
    @Environment(ConnectionManager.self) var connection
    @Environment(DirectoryBrowserModel.self) var model
    @Environment(\.dismiss) var dismiss

    /// Called with the absolute path when the user taps "Use Folder".
    let onSelect: (String) -> Void

    /// Initial path to display (nil = home).
    let initialPath: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                content
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSelect(model.currentPath)
                        dismiss()
                    } label: {
                        Text("Use")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .tint(Theme.accent)
                }
            }
            .onAppear {
                if model.currentPath.isEmpty {
                    model.navigate(to: initialPath, connection: connection)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var navigationTitle: String {
        if model.currentPath.isEmpty { return "Folder" }
        return (model.currentPath as NSString).lastPathComponent.isEmpty
            ? "/"
            : (model.currentPath as NSString).lastPathComponent
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            pathBar
            Divider().background(Theme.stroke)
            listSection
        }
    }

    private var pathBar: some View {
        @Bindable var model = model
        return HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.textSecondary)
                .font(.system(size: 11))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(prettyPath(model.currentPath))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $model.showHidden)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .scaleEffect(0.75)
            Text("Hidden")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var listSection: some View {
        switch model.state {
        case .loading where model.entries.isEmpty:
            VStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }
        case .error(let msg):
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
        default:
            List {
                if canGoUp {
                    Button {
                        model.navigate(to: parentPath, connection: connection)
                    } label: {
                        Label("..", systemImage: "arrow.up.left")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Color.white.opacity(0.03))
                }
                ForEach(model.entries) { entry in
                    EntryRow(entry: entry, parentPath: model.currentPath) {
                        guard entry.isDirectory else { return }
                        let next = childPath(entry: entry)
                        model.navigate(to: next, connection: connection)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.stroke)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    private var canGoUp: Bool {
        guard !model.currentPath.isEmpty else { return false }
        return model.currentPath != "/"
    }

    private var parentPath: String {
        (model.currentPath as NSString).deletingLastPathComponent
    }

    private func childPath(entry: DirectoryEntry) -> String {
        (model.currentPath as NSString).appendingPathComponent(entry.name)
    }

    private func prettyPath(_ path: String) -> String {
        // Replace home prefix with ~ for compactness in the breadcrumb.
        // We don't know the Mac's home here, but a heuristic: paths starting
        // with /Users/<name> render the home segment as ~.
        if path.hasPrefix("/Users/") {
            // /Users/foo/bar -> ~/bar
            let comps = path.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: true)
            if comps.count >= 2 {
                let rest = comps.count >= 3 ? "/" + comps[2] : ""
                return "~" + rest
            }
            return path
        }
        return path
    }
}

private struct EntryRow: View {
    let entry: DirectoryEntry
    let parentPath: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.04)).frame(width: 30, height: 30)
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(entry.isDirectory ? Theme.accent : Theme.textTertiary)
                }
                Text(entry.name)
                    .font(.system(size: 14, weight: entry.isDirectory ? .semibold : .regular))
                    .foregroundStyle(entry.isDirectory ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!entry.isDirectory)
    }
}
