// server/Sources/DirectoryListingService.swift
import Foundation
import MaverickProtocol

/// Lists directories on the Mac with an in-memory cache (10s TTL) so the iOS
/// browser stays snappy when the user drills in and out.
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

    private struct CacheEntry {
        let entries: [DirectoryEntry]
        let timestamp: Date
    }

    private let cache = NSCache<NSString, NSData>()
    private var cacheKeys: [String: Date] = [:]
    private let cacheLock = NSLock()
    private let ttl: TimeInterval = 10

    func list(path: String?) throws -> (path: String, entries: [DirectoryEntry]) {
        let resolved = Self.resolve(path: path)

        // Cache check
        cacheLock.lock()
        let cachedDate = cacheKeys[resolved]
        cacheLock.unlock()
        if let cachedDate, Date().timeIntervalSince(cachedDate) < ttl,
           let data = cache.object(forKey: resolved as NSString),
           let cached = try? JSONDecoder().decode([DirectoryEntry].self, from: data as Data) {
            return (resolved, cached)
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolved, isDirectory: &isDir) else {
            throw ListingError.notAccessible("Path does not exist: \(resolved)")
        }
        guard isDir.boolValue else {
            throw ListingError.notADirectory(resolved)
        }

        let names: [String]
        do {
            names = try fm.contentsOfDirectory(atPath: resolved)
        } catch {
            throw ListingError.notAccessible(error.localizedDescription)
        }

        let entries: [DirectoryEntry] = names.map { name in
            var childIsDir: ObjCBool = false
            let full = (resolved as NSString).appendingPathComponent(name)
            fm.fileExists(atPath: full, isDirectory: &childIsDir)
            return DirectoryEntry(
                name: name,
                isDirectory: childIsDir.boolValue,
                isHidden: name.hasPrefix(".")
            )
        }
        .sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        // Persist to cache
        if let encoded = try? JSONEncoder().encode(entries) {
            cache.setObject(encoded as NSData, forKey: resolved as NSString)
            cacheLock.lock()
            cacheKeys[resolved] = Date()
            cacheLock.unlock()
        }

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
}
