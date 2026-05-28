// client/Sources/Features/Explorer/ProjectIndexModel.swift
import Foundation
import Observation
import MaverickProtocol

/// Drives the file-explorer tab. Streams index chunks from the server,
/// dedupes by path, and exposes a tree view of the project rooted at `root`.
@Observable
final class ProjectIndexModel {
    enum State: Equatable { case idle, loading, loaded, error(String) }

    /// Absolute root path of the most recent successful index.
    private(set) var root: String = ""
    private(set) var state: State = .idle

    /// All collected entries, in order of arrival.
    private(set) var entries: [IndexEntry] = []

    /// Toggle to include dot files in the tree.
    var showHidden: Bool = false

    private var entrySet: Set<String> = []
    private var pendingRequestId: UUID?

    /// Index the given absolute path. If we're already showing this path,
    /// pass `refresh=true` to bypass the server's index cache.
    func index(path: String, refresh: Bool = false, connection: ConnectionManager) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == root && state == .loaded && !refresh { return }
        let req = UUID()
        pendingRequestId = req
        state = .loading
        entries.removeAll()
        entrySet.removeAll()
        connection.send(.indexProject(requestId: req, path: trimmed, refresh: refresh))
    }

    func handle(_ message: ServerMessage) {
        switch message {
        case .indexChunk(let reqId, let root, let chunkEntries, let complete):
            guard reqId == pendingRequestId else { return }
            self.root = root
            for entry in chunkEntries where entrySet.insert(entry.path).inserted {
                entries.append(entry)
            }
            if complete {
                state = .loaded
                pendingRequestId = nil
            }
        case .indexFailed(let reqId, let msg):
            guard reqId == pendingRequestId else { return }
            state = .error(msg)
            pendingRequestId = nil
        default:
            break
        }
    }

    /// Returns entries whose parent directory equals `parent` (relative path).
    /// Empty `parent` means root-level entries.
    func children(of parent: String) -> [IndexEntry] {
        let prefix = parent.isEmpty ? "" : parent + "/"
        return entries.filter { entry in
            guard entry.path.hasPrefix(prefix) else { return false }
            let remainder = String(entry.path.dropFirst(prefix.count))
            // direct child: no more "/" in the remainder
            return !remainder.isEmpty && !remainder.contains("/")
        }
        .filter { showHidden || !$0.path.split(separator: "/").last!.hasPrefix(".") }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
    }
}
