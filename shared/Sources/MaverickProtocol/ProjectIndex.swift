// shared/Sources/MaverickProtocol/ProjectIndex.swift
import Foundation

/// A single entry in a project index. `path` is relative to the project root
/// (forward-slash separators), e.g. "src/foo/bar.swift" or "node_modules".
public struct IndexEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let path: String
    public let isDirectory: Bool
    public let size: Int64?

    public var id: String { path }

    public init(path: String, isDirectory: Bool, size: Int64? = nil) {
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
    }
}

public struct GitFileStatus: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let path: String
    /// Single-letter git porcelain code: M (modified), A (added), D (deleted),
    /// R (renamed), C (copied), U (unmerged), ? (untracked).
    public let status: String
    /// True if this entry is in the index (staged), false if in the working tree.
    public let staged: Bool

    public var id: String { (staged ? "S:" : "U:") + path }

    public init(path: String, status: String, staged: Bool) {
        self.path = path
        self.status = status
        self.staged = staged
    }
}

public struct GitStatus: Codable, Equatable, Sendable {
    public let isRepo: Bool
    public let branch: String?
    public let ahead: Int
    public let behind: Int
    public let files: [GitFileStatus]

    public init(isRepo: Bool, branch: String?, ahead: Int, behind: Int, files: [GitFileStatus]) {
        self.isRepo = isRepo
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.files = files
    }

    public static let notARepo = GitStatus(isRepo: false, branch: nil, ahead: 0, behind: 0, files: [])
}
