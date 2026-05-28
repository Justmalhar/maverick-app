// server/Sources/GitWrapper.swift
import Foundation
import MaverickProtocol

/// Shells out to /usr/bin/git for status + diff. Cheap, no third-party deps.
/// `git status` is cached briefly (5s); `git diff` is always fresh.
final class GitWrapper: @unchecked Sendable {
    enum GitError: LocalizedError {
        case notFound
        case invalidPath(String)
        case execFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "git not found at /usr/bin/git or /opt/homebrew/bin/git"
            case .invalidPath(let p): return "Invalid repo path: \(p)"
            case .execFailed(let code, let msg):
                return "git exited \(code): \(msg.isEmpty ? "(no output)" : msg)"
            }
        }
    }

    /// 256KB cap on diff bytes so a giant generated diff doesn't blow up the
    /// WebSocket frame. iOS limit is 16MB but we'd rather render fast.
    static let maxDiffBytes = 256 * 1024

    private let statusCacheLock = NSLock()
    private var statusCache: [String: (GitStatus, Date)] = [:]
    private let statusTTL: TimeInterval = 5

    // MARK: - status

    /// Runs `git status --porcelain=v2 --branch` and parses the result.
    /// Returns `GitStatus.notARepo` if the path isn't inside a git repo.
    func status(path: String) throws -> GitStatus {
        let resolved = DirectoryListingService.resolve(path: path)

        statusCacheLock.lock()
        if let (cached, ts) = statusCache[resolved], Date().timeIntervalSince(ts) < statusTTL {
            statusCacheLock.unlock()
            return cached
        }
        statusCacheLock.unlock()

        guard FileManager.default.fileExists(atPath: resolved) else {
            throw GitError.invalidPath(resolved)
        }

        // Detect repo first; cheap and clean.
        let inside = try runGit(args: ["rev-parse", "--is-inside-work-tree"], cwd: resolved)
        guard inside.exit == 0,
              inside.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            let notRepo = GitStatus.notARepo
            cacheStatus(resolved, notRepo)
            return notRepo
        }

        let result = try runGit(args: ["status", "--porcelain=v2", "--branch"], cwd: resolved)
        guard result.exit == 0 else {
            throw GitError.execFailed(result.exit, result.stderr)
        }
        let parsed = Self.parsePorcelainV2(result.stdout)
        cacheStatus(resolved, parsed)
        return parsed
    }

    private func cacheStatus(_ path: String, _ status: GitStatus) {
        statusCacheLock.lock(); defer { statusCacheLock.unlock() }
        statusCache[path] = (status, Date())
    }

    // MARK: - diff

    /// Runs `git diff [--cached] -- <file>` from the repo root. Returns the
    /// patch text; truncates at maxDiffBytes to keep frames small.
    func diff(path: String, file: String, staged: Bool) throws -> (diff: String, truncated: Bool) {
        let resolved = DirectoryListingService.resolve(path: path)
        var args = ["diff", "--no-color"]
        if staged { args.append("--cached") }
        args.append(contentsOf: ["--", file])
        let result = try runGit(args: args, cwd: resolved)
        guard result.exit == 0 else {
            throw GitError.execFailed(result.exit, result.stderr)
        }
        if result.stdout.utf8.count > Self.maxDiffBytes {
            let truncated = String(result.stdout.prefix(Self.maxDiffBytes))
            return (truncated, true)
        }
        return (result.stdout, false)
    }

    // MARK: - subprocess helper

    private struct ProcResult { let exit: Int32; let stdout: String; let stderr: String }

    private func runGit(args: [String], cwd: String) throws -> ProcResult {
        let candidates = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        guard let gitPath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw GitError.notFound
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: gitPath)
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        try task.run()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        return ProcResult(
            exit: task.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    // MARK: - parsing porcelain v2
    //
    // Line formats we care about:
    //   # branch.head main
    //   # branch.ab +3 -1
    //   1 XY ... <path>            (regular changed file; XY = staged/unstaged status)
    //   2 XY ... <orig>\t<new>     (renamed/copied)
    //   ? <path>                   (untracked)
    //   u XY ... <path>            (unmerged)
    //
    // Reference: https://git-scm.com/docs/git-status#_porcelain_format_version_2

    static func parsePorcelainV2(_ raw: String) -> GitStatus {
        var branch: String? = nil
        var ahead = 0
        var behind = 0
        var files: [GitFileStatus] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.head ") {
                branch = String(line.dropFirst("# branch.head ".count))
            } else if line.hasPrefix("# branch.ab ") {
                // e.g. "+3 -1"
                let nums = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for token in nums {
                    if token.hasPrefix("+") { ahead  = Int(token.dropFirst()) ?? 0 }
                    if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") {
                // 1 XY <submodule> <mH> <mI> <mW> <hH> <hI> <path>
                let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard parts.count >= 9 else { continue }
                let xy = String(parts[1])
                let path = String(parts[8])
                let staged = String(xy.first ?? ".")
                let unstaged = String(xy.last  ?? ".")
                if staged != "." { files.append(GitFileStatus(path: path, status: staged, staged: true)) }
                if unstaged != "." { files.append(GitFileStatus(path: path, status: unstaged, staged: false)) }
            } else if line.hasPrefix("2 ") {
                // Rename/copy. Path is "<new>\t<orig>".
                let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard parts.count >= 10 else { continue }
                let xy = String(parts[1])
                let pathPair = String(parts[9])
                let newPath = pathPair.split(separator: "\t").first.map(String.init) ?? pathPair
                let staged = String(xy.first ?? ".")
                let unstaged = String(xy.last  ?? ".")
                if staged != "." { files.append(GitFileStatus(path: newPath, status: staged, staged: true)) }
                if unstaged != "." { files.append(GitFileStatus(path: newPath, status: unstaged, staged: false)) }
            } else if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2))
                files.append(GitFileStatus(path: path, status: "?", staged: false))
            } else if line.hasPrefix("u ") {
                let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard parts.count >= 11 else { continue }
                let path = String(parts[10])
                files.append(GitFileStatus(path: path, status: "U", staged: false))
            }
        }
        return GitStatus(isRepo: true, branch: branch, ahead: ahead, behind: behind, files: files)
    }
}
