// server/Sources/HookConfigWriter.swift
import Foundation

/// Merges Maverick's HTTP hook endpoints into `~/.claude/settings.json` on startup.
///
/// Existing hooks are preserved. If the Maverick endpoint is already present for
/// a given event, no duplicate is added. The file is created if it does not exist.
enum HookConfigWriter {

    private static let hookURL = "http://localhost:7789/hook"
    private static let settingsPath = ("~/.claude/settings.json" as NSString).expandingTildeInPath

    /// All hook events Maverick handles, paired with their timeout values.
    private static let maverickHooks: [(event: String, timeout: Int)] = [
        ("PreToolUse",        10),
        ("PostToolUse",       10),
        ("PostToolUseFailure",10),
        ("PostToolBatch",     10),
        ("PermissionRequest", 30),
        ("PermissionDenied",  10),
        ("Stop",              10),
        ("SubagentStart",     10),
        ("SubagentStop",      10),
        ("SessionStart",      10),
        ("Notification",      10),
        ("TaskCreated",       10),
        ("TaskCompleted",     10),
    ]

    /// Writes Maverick hook config to `~/.claude/settings.json`, merging with any existing content.
    static func install() {
        do {
            try writeHooks()
            NSLog("[HookConfigWriter] Hook config merged into %@", settingsPath)
        } catch {
            NSLog("[HookConfigWriter] Failed to write hook config: %@", error.localizedDescription)
        }
    }

    // MARK: - Private

    private static func writeHooks() throws {
        let url = URL(fileURLWithPath: settingsPath)

        // Load existing settings or start fresh.
        // Distinguish "file missing" (safe to create) from "file corrupt" (must not clobber).
        var settings: [String: Any]
        if FileManager.default.fileExists(atPath: settingsPath) {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            settings = json
        } else {
            settings = [:]
        }

        // Ensure the parent directory exists (~/.claude/)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Merge hooks
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in maverickHooks {
            hooks[event] = mergedHookList(existing: hooks[event], event: event, timeout: timeout)
        }
        settings["hooks"] = hooks

        // Write back as pretty-printed JSON
        let outputData = try JSONSerialization.data(withJSONObject: settings,
                                                    options: [.prettyPrinted, .sortedKeys])
        try outputData.write(to: url, options: .atomic)
    }

    /// Returns the merged hook list for one event, ensuring Maverick's entry is present exactly once.
    private static func mergedHookList(existing: Any?, event: String, timeout: Int) -> [[String: Any]] {
        var list: [[String: Any]]
        if let arr = existing as? [[String: Any]] {
            list = arr
        } else {
            list = []
        }

        // Check if our endpoint is already registered for this event
        let alreadyPresent = list.contains { entry in
            guard let innerHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return innerHooks.contains { h in (h["url"] as? String) == hookURL }
        }

        if !alreadyPresent {
            let maverickEntry: [String: Any] = [
                "hooks": [
                    ["type": "http", "url": hookURL, "timeout": timeout]
                ]
            ]
            list.append(maverickEntry)
        }
        return list
    }
}
