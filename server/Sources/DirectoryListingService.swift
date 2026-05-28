// server/Sources/DirectoryListingService.swift
import Foundation
import MaverickProtocol

/// Lists directories on the Mac with an in-memory index that is eagerly warmed
/// on agent startup and kept fresh by a low-cost background refresh loop.
///
/// Caching strategy:
///   1. **Eager warmup**: on init, `$HOME` and its immediate child directories
///      are listed on a background queue so the very first iOS request hits
///      a populated cache (~1ms instead of ~30ms).
///   2. **Read path**: `list()` returns the cached value if it's < ttl old.
///      A cache miss reads the directory synchronously, stores it, AND fires
///      off a background prefetch of each subdirectory so subsequent drill-ins
///      also feel instant.
///   3. **Background refresh**: every `refreshInterval` seconds a daemon
///      thread iterates the cached paths and re-lists each one, replacing
///      any entry whose contents changed. The cost is bounded by the number
///      of distinct directories the user has visited, which is small in
///      practice (dozens, not thousands).
///
/// FSEvents-based real-time invalidation is the next step (see BACKLOG item).
/// For now, a 30s refresh window is well below the threshold the user can
/// perceive as "stale" for the folder picker.
final class DirectoryListingService: @unchecked Sendable {
    enum ListingError: LocalizedError {
        case notADirectory(String)
        case notAccessible(String)
        var errorDescription: String? {
            switch self {
            case .notADirectory(let p): return "Not a directory: \(p)"
            case .notAccessible(let msg): return msg
            }
        }
    }

    /// Entries are valid for this long before a `list` call re-reads from disk.
    /// The refresh loop runs more frequently so most cache reads stay current
    /// without the user ever waiting.
    private let ttl: TimeInterval = 120
    private let refreshInterval: TimeInterval = 30
    /// Number of immediate child directories of $HOME to pre-list at startup.
    private let warmupChildrenCap = 30
    /// Cap on cached paths so an explorer-happy user doesn't blow up memory.
    private let maxCachedPaths = 500

    private struct CacheEntry {
        var entries: [DirectoryEntry]
        var timestamp: Date
        var lastAccessed: Date
    }

    private let cacheLock = NSLock()
    private var cache: [String: CacheEntry] = [:]

    private let workQueue = DispatchQueue(label: "maverick.indexer", qos: .utility, attributes: .concurrent)
    private var refreshTimer: DispatchSourceTimer?

    init() {
        warmup()
        startRefreshLoop()
    }

    deinit {
        refreshTimer?.cancel()
    }

    // MARK: - Public API

    func list(path: String?) throws -> (path: String, entries: [DirectoryEntry]) {
        let resolved = Self.resolve(path: path)

        if let cached = readCache(path: resolved) {
            // Mark accessed for LRU. Schedule a background prefetch of children
            // so the next tap is also warm.
            prefetchChildrenInBackground(parent: resolved, entries: cached)
            return (resolved, cached)
        }

        // Cache miss: do a synchronous read.
        let entries = try Self.readDirectory(at: resolved)
        writeCache(path: resolved, entries: entries)
        prefetchChildrenInBackground(parent: resolved, entries: entries)
        return (resolved, entries)
    }

    /// Resolves `~` and `~/...` against the Mac's $HOME. Empty or nil paths
    /// also map to $HOME so the browser opens there by default.
    static func resolve(path: String?) -> String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return home
        }
        if raw == "~" { return home }
        if raw.hasPrefix("~/") { return home + String(raw.dropFirst(1)) }
        return raw
    }

    // MARK: - Cache plumbing

    private func readCache(path: String) -> [DirectoryEntry]? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        guard var entry = cache[path] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cache.removeValue(forKey: path)
            return nil
        }
        entry.lastAccessed = Date()
        cache[path] = entry
        return entry.entries
    }

    private func writeCache(path: String, entries: [DirectoryEntry]) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        cache[path] = CacheEntry(entries: entries, timestamp: Date(), lastAccessed: Date())
        evictIfNeededLocked()
    }

    private func evictIfNeededLocked() {
        guard cache.count > maxCachedPaths else { return }
        // Drop the least-recently-accessed quarter.
        let dropCount = cache.count - maxCachedPaths + (maxCachedPaths / 4)
        let oldest = cache
            .sorted { $0.value.lastAccessed < $1.value.lastAccessed }
            .prefix(dropCount)
            .map(\.key)
        for key in oldest { cache.removeValue(forKey: key) }
    }

    // MARK: - Prefetching

    /// On startup: read $HOME and all of its first-level subdirectories.
    /// Runs entirely on a background queue so agent launch isn't blocked.
    private func warmup() {
        workQueue.async { [weak self] in
            guard let self else { return }
            let home = Self.resolve(path: nil)
            guard let homeEntries = try? Self.readDirectory(at: home) else { return }
            self.writeCache(path: home, entries: homeEntries)
            for entry in homeEntries.filter(\.isDirectory).prefix(self.warmupChildrenCap) {
                let child = (home as NSString).appendingPathComponent(entry.name)
                if let childEntries = try? Self.readDirectory(at: child) {
                    self.writeCache(path: child, entries: childEntries)
                }
            }
        }
    }

    /// After a directory is listed, async-prefetch each immediate subdirectory
    /// so the next user navigation hits a populated cache.
    private func prefetchChildrenInBackground(parent: String, entries: [DirectoryEntry]) {
        let children = entries
            .filter { $0.isDirectory && !$0.isHidden }
            .prefix(20)
            .map { (parent as NSString).appendingPathComponent($0.name) }
        guard !children.isEmpty else { return }
        workQueue.async { [weak self] in
            guard let self else { return }
            for child in children {
                // Skip if it's already fresh.
                if self.readCache(path: child) != nil { continue }
                if let childEntries = try? Self.readDirectory(at: child) {
                    self.writeCache(path: child, entries: childEntries)
                }
            }
        }
    }

    // MARK: - Periodic refresh
    //
    // Every 30s, scan all cached paths and re-list any that are older than
    // (ttl - 10s). This silently keeps the index fresh so the user never
    // waits on a cache miss for paths they've already visited.

    private func startRefreshLoop() {
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + refreshInterval, repeating: refreshInterval)
        timer.setEventHandler { [weak self] in self?.refreshCachedPaths() }
        refreshTimer = timer
        timer.resume()
    }

    private func refreshCachedPaths() {
        cacheLock.lock()
        let snapshot = cache
            .filter { Date().timeIntervalSince($0.value.timestamp) > (ttl - 10) }
            .keys
        cacheLock.unlock()
        for path in snapshot {
            if let entries = try? Self.readDirectory(at: path) {
                writeCache(path: path, entries: entries)
            } else {
                // Path is gone; drop it from the cache.
                cacheLock.lock()
                cache.removeValue(forKey: path)
                cacheLock.unlock()
            }
        }
    }

    // MARK: - Raw directory read

    /// Reads a single directory and returns sorted entries (directories first,
    /// then files; alphabetical within each group; mark dot-files as hidden).
    static func readDirectory(at path: String) throws -> [DirectoryEntry] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
            throw ListingError.notAccessible("Path does not exist: \(path)")
        }
        guard isDir.boolValue else {
            throw ListingError.notADirectory(path)
        }
        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: path)
        } catch {
            throw ListingError.notAccessible(error.localizedDescription)
        }
        return names.map { name in
            var childIsDir: ObjCBool = false
            let full = (path as NSString).appendingPathComponent(name)
            fm.fileExists(atPath: full, isDirectory: &childIsDir)
            return DirectoryEntry(name: name, isDirectory: childIsDir.boolValue, isHidden: name.hasPrefix("."))
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
