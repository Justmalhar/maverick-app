// client/Sources/Features/Sessions/SessionStore.swift
import Foundation
import MaverickProtocol

@Observable
final class SessionStore {
    var sessions: [SessionInfo] = []
    var activeSessionId: UUID?
    var outputHandlers: [UUID: (Data) -> Void] = [:]
    /// Live working directory per session, as reported by the shell's OSC 7
    /// escape sequence (`\e]7;file://host/path\e\\`). The Files tab re-indexes
    /// whenever the entry for its session changes.
    var sessionCwds: [UUID: String] = [:]

    func updateCwd(sessionId: UUID, cwd: String) {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if sessionCwds[sessionId] != trimmed {
            sessionCwds[sessionId] = trimmed
        }
    }

    func handle(_ message: ServerMessage) {
        switch message {
        case .sessionList(let list):
            sessions = list
        case .sessionCreated(let info):
            if !sessions.contains(where: { $0.id == info.id }) {
                sessions.append(info)
            }
        case .sessionClosed(let id):
            sessions.removeAll { $0.id == id }
            if activeSessionId == id { activeSessionId = nil }
            outputHandlers.removeValue(forKey: id)
        case .output(let id, let b64):
            if let data = Data(base64Encoded: b64) {
                outputHandlers[id]?(data)
            }
        case .scrollback(let id, let b64):
            if let data = Data(base64Encoded: b64) {
                outputHandlers[id]?(data)
            }
        case .error(let msg):
            print("[SessionStore] server error: \(msg)")
        case .fileUploaded, .fileUploadFailed:
            // Handled by AttachmentManager.
            break
        case .directoryListing, .directoryListingFailed:
            // Handled by DirectoryBrowserModel.
            break
        case .indexChunk, .indexFailed:
            // Handled by ProjectIndexModel.
            break
        case .gitStatusResult, .gitStatusFailed, .gitDiffResult, .gitDiffFailed:
            // Handled by GitStatusModel.
            break
        }
    }

    func registerOutputHandler(sessionId: UUID, handler: @escaping (Data) -> Void) {
        outputHandlers[sessionId] = handler
    }
}
