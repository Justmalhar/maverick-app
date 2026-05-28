// server/Sources/ProjectIndexer.swift
import Foundation
import MaverickProtocol

/// Walks a project directory and streams entries back in chunks via a callback.
/// Skips heavy / generated directories so the index stays small and snappy.
/// In-memory cache keyed by absolute root path; bounded to ~3 most recent
/// projects (each capped at 5000 entries).
final class ProjectIndexer: @unchecked Sendable {
    /// Names we never descend into. Cheap heuristic; we can swap in
    /// `git check-ignore --stdin` later for full .gitignore support.
    static let skipSet: Set<String> = [
        ".git", "node_modules", ".next", "dist", "build",
        ".venv", "venv", "__pycache__", "Pods", ".DS_Store",
        ".turbo", ".vercel", ".idea", ".vscode-test", ".gradle",
        "target", ".cache", "coverage", ".pytest_cache"
    ]

    static let maxEntries = 5_000
    static let chunkSize = 200
    static let cacheCapacity = 3

    private struct CacheEntry {
        let root: String
        let entries: [IndexEntry]
        let timestamp: Date
    }

    private let cacheLock = NSLock()
    private var cache: [String: CacheEntry] = [:]
    private var cacheOrder: [String] = []
    /// Cache TTL — 60s is plenty; user can force-refresh via `refresh=true`.
    private let ttl: TimeInterval = 60

    /// Drives the streaming index. `onChunk` is called with each batch of
    /// entries; the final call has `complete=true`. If a cache hit exists
    /// (and `refresh==false`), the cached entries are delivered in one
    /// chunk with `complete=true` and the walk is skipped.
    func index(
        path: String,
        refresh: Bool,
        onChunk: @escaping (_ root: String, _ entries: [IndexEntry], _ complete: Bool) -> Void
    ) {
        let resolved = DirectoryListingService.resolve(path: path)

        if !refresh, let cached = readCache(root: resolved) {
            onChunk(resolved, cached, true)
            return
        }

        // Walk on a background queue so the WebSocket queue stays responsive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var collected: [IndexEntry] = []
            var batch: [IndexEntry] = []
            var truncated = false
            self.walk(root: resolved, current: resolved) { entry in
                collected.append(entry)
                batch.append(entry)
                if collected.count >= Self.maxEntries {
                    truncated = true
                    return false
                }
                if batch.count >= Self.chunkSize {
                    onChunk(resolved, batch, false)
                    batch.removeAll(keepingCapacity: true)
                }
                return true
            }
            // Final chunk + cache write.
            onChunk(resolved, batch, true)
            _ = truncated  // can surface in a separate notification if desired
            self.writeCache(root: resolved, entries: collected)
        }
    }

    // MARK: - Walk

    /// Depth-first walk emitting one IndexEntry per encountered file/folder.
    /// `visit` returns false to halt the walk early (e.g. maxEntries reached).
    private func walk(
        root: String,
        current: String,
        visit: (IndexEntry) -> Bool
    ) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(atPath: current) else { return }
        let sorted = children.sorted()  // deterministic order
        for name in sorted {
            if Self.skipSet.contains(name) { continue }
            let full = (current as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            let rel = relativePath(root: root, full: full)
            let size: Int64? = isDir.boolValue
                ? nil
                : ((try? fm.attributesOfItem(atPath: full)[.size]) as? Int64)
            let entry = IndexEntry(path: rel, isDirectory: isDir.boolValue, size: size)
            if !visit(entry) { return }
            if isDir.boolValue {
                walk(root: root, current: full, visit: visit)
            }
        }
    }

    private func relativePath(root: String, full: String) -> String {
        if full.hasPrefix(root + "/") { return String(full.dropFirst(root.count + 1)) }
        if full == root { return "" }
        return full
    }

    // MARK: - Cache

    private func readCache(root: String) -> [IndexEntry]? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        guard let entry = cache[root] else { return nil }
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            cache.removeValue(forKey: root)
            cacheOrder.removeAll { $0 == root }
            return nil
        }
        return entry.entries
    }

    private func writeCache(root: String, entries: [IndexEntry]) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if cache[root] != nil {
            cacheOrder.removeAll { $0 == root }
        } else if cacheOrder.count >= Self.cacheCapacity, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache.removeValue(forKey: oldest)
        }
        cache[root] = CacheEntry(root: root, entries: entries, timestamp: Date())
        cacheOrder.append(root)
    }
}
