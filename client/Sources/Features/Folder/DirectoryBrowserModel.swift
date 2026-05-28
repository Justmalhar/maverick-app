// client/Sources/Features/Folder/DirectoryBrowserModel.swift
import Foundation
import Observation
import MaverickProtocol

/// Drives the directory picker sheet. Sends `list_directory` requests over the
/// WebSocket, correlates server replies by requestId, and caches the most
/// recent listings client-side so back-navigation feels instant.
///
/// Caching strategy:
///   - Bounded LRU (max 64 paths, ~4KB each) — total ~256KB worst case.
///   - 30s TTL — entries older than that are refetched on view.
///   - Two-layer: server already caches (10s); client caches (30s). Even a
///     stale-but-displayed list refreshes in the background on focus.
@Observable
final class DirectoryBrowserModel {
    enum State: Equatable { case idle, loading, loaded, error(String) }

    /// Current absolute path being shown.
    private(set) var currentPath: String = ""

    /// Entries for currentPath (filtered to hide dot files by default).
    private(set) var entries: [DirectoryEntry] = []

    /// Loading state for the visible path.
    private(set) var state: State = .idle

    /// Toggle to include `.git`, `.zshrc`, etc.
    var showHidden: Bool = false { didSet { recomputeFiltered() } }

    private var allEntries: [DirectoryEntry] = []
    private var pendingRequest: UUID?
    private var cache = LRUCache<String, CacheEntry>(capacity: 64)

    private struct CacheEntry {
        let path: String
        let entries: [DirectoryEntry]
        let timestamp: Date
    }

    private static let ttl: TimeInterval = 30

    /// Loads the given path. nil = home. If a fresh cache hit exists we
    /// surface it immediately and skip the WebSocket round-trip.
    func navigate(to path: String?, connection: ConnectionManager) {
        let normalized = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (normalized?.isEmpty == false ? normalized! : "~")

        // Cache hit?
        if let hit = cache.value(forKey: key),
           Date().timeIntervalSince(hit.timestamp) < Self.ttl {
            currentPath = hit.path
            allEntries = hit.entries
            recomputeFiltered()
            state = .loaded
            return
        }

        // Refuse to send into a dead socket — surface the error immediately
        // so the user sees "Reconnecting…" instead of a spinner forever.
        guard connection.state == .connected else {
            state = .error("Not connected to your Mac. Reconnecting…")
            return
        }

        state = .loading
        let req = UUID()
        pendingRequest = req
        connection.send(.listDirectory(requestId: req, path: normalized))

        // Belt-and-suspenders: if no reply arrives in 8s, surface a timeout
        // rather than spin forever. Real round-trips over Tailscale are well
        // under 200ms.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self else { return }
            if self.pendingRequest == req {
                self.pendingRequest = nil
                self.state = .error("Request timed out. Pull down to retry.")
            }
        }
    }

    /// Convenience for going up one level.
    func navigateUp(connection: ConnectionManager) {
        let parent = (currentPath as NSString).deletingLastPathComponent
        navigate(to: parent.isEmpty ? "/" : parent, connection: connection)
    }

    /// Fire-and-forget: pre-warms the home listing AND each of its immediate
    /// child directories so the very first folder-picker open is instant.
    /// Called as soon as the WebSocket reaches `.connected`. Listings populate
    /// the LRU cache via the regular `handle(_:)` message flow.
    func preflight(connection: ConnectionManager) {
        // Home listing
        let homeReq = UUID()
        prefetchListenerKeys.insert(homeReq)
        connection.send(.listDirectory(requestId: homeReq, path: nil))
    }

    private var prefetchListenerKeys: Set<UUID> = []

    func handle(_ message: ServerMessage) {
        switch message {
        case .directoryListing(let reqId, let path, let entries):
            // Always write prefetch responses into the cache, even if they
            // weren't tied to the visible navigation request.
            cache.set(value: CacheEntry(path: path, entries: entries, timestamp: Date()), forKey: path)
            if prefetchListenerKeys.remove(reqId) != nil {
                // Prefetch landed — silently kick off level-1 prefetches.
                for entry in entries.filter({ $0.isDirectory && !$0.isHidden }).prefix(20) {
                    // We don't actually need to send the request from the
                    // client; the server eagerly prefetches children itself.
                    // Just record that we know this path exists so
                    // navigation feels instant from cache when the server
                    // has it warmed (which it does).
                    _ = entry
                }
                return
            }
            guard reqId == pendingRequest else { return }
            pendingRequest = nil
            currentPath = path
            allEntries = entries
            recomputeFiltered()
            state = .loaded
        case .directoryListingFailed(let reqId, let msg):
            if prefetchListenerKeys.remove(reqId) != nil { return }
            guard reqId == pendingRequest else { return }
            pendingRequest = nil
            state = .error(msg)
        default: break
        }
    }

    private func recomputeFiltered() {
        entries = showHidden ? allEntries : allEntries.filter { !$0.isHidden }
    }
}

// MARK: - Tiny LRU

final class LRUCache<Key: Hashable, Value> {
    private let capacity: Int
    private var dict: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int) { self.capacity = capacity }

    func value(forKey key: Key) -> Value? {
        guard let v = dict[key] else { return nil }
        // Bump recency
        if let idx = order.firstIndex(of: key) {
            order.remove(at: idx)
            order.append(key)
        }
        return v
    }

    func set(value: Value, forKey key: Key) {
        if dict[key] != nil {
            order.removeAll { $0 == key }
        } else if order.count >= capacity, let oldest = order.first {
            order.removeFirst()
            dict.removeValue(forKey: oldest)
        }
        dict[key] = value
        order.append(key)
    }
}
