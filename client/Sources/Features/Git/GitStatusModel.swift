// client/Sources/Features/Git/GitStatusModel.swift
import Foundation
import Observation
import MaverickProtocol

/// Drives the git diff tab. Holds the current GitStatus + a map of cached
/// diffs per file. Diffs are fetched on demand (when the user taps a file
/// in the list).
@Observable
final class GitStatusModel {
    enum State: Equatable { case idle, loading, loaded, error(String) }

    private(set) var path: String = ""
    private(set) var state: State = .idle
    private(set) var status: GitStatus = .notARepo

    /// Diff text per file (UI side cache, keyed by "<staged?>:<path>" so
    /// staged vs working-tree diffs don't collide).
    private(set) var diffs: [String: DiffResult] = [:]
    /// Files currently being fetched, for spinner display.
    private(set) var pendingDiffs: Set<String> = []

    struct DiffResult: Equatable {
        let text: String
        let truncated: Bool
    }

    private var pendingStatusRequestId: UUID?
    private var pendingDiffRequests: [UUID: String] = [:]   // requestId -> diffKey

    static func key(file: String, staged: Bool) -> String { (staged ? "S:" : "U:") + file }

    func refresh(path: String, connection: ConnectionManager) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let req = UUID()
        pendingStatusRequestId = req
        state = .loading
        self.path = trimmed
        connection.send(.gitStatus(requestId: req, path: trimmed))
    }

    func fetchDiff(file: String, staged: Bool, connection: ConnectionManager) {
        let key = Self.key(file: file, staged: staged)
        // Skip if already cached or in flight.
        if diffs[key] != nil { return }
        if pendingDiffs.contains(key) { return }
        let req = UUID()
        pendingDiffRequests[req] = key
        pendingDiffs.insert(key)
        connection.send(.gitDiff(requestId: req, path: path, file: file, staged: staged))
    }

    func handle(_ message: ServerMessage) {
        switch message {
        case .gitStatusResult(let reqId, let s):
            guard reqId == pendingStatusRequestId else { return }
            status = s
            state = .loaded
            pendingStatusRequestId = nil
        case .gitStatusFailed(let reqId, let msg):
            guard reqId == pendingStatusRequestId else { return }
            state = .error(msg)
            pendingStatusRequestId = nil
        case .gitDiffResult(let reqId, _, let diff, let truncated):
            guard let key = pendingDiffRequests.removeValue(forKey: reqId) else { return }
            pendingDiffs.remove(key)
            diffs[key] = DiffResult(text: diff, truncated: truncated)
        case .gitDiffFailed(let reqId, let msg):
            guard let key = pendingDiffRequests.removeValue(forKey: reqId) else { return }
            pendingDiffs.remove(key)
            diffs[key] = DiffResult(text: "[diff failed] \(msg)", truncated: false)
        default:
            break
        }
    }
}
