// client/Sources/Features/Tasks/AttachmentManager.swift
import Foundation
import Observation
import MaverickProtocol

@Observable
final class AttachmentManager {
    struct Attachment: Identifiable, Equatable {
        let id: UUID
        let filename: String
        var status: Status

        enum Status: Equatable {
            case uploading
            case ready(path: String)
            case failed(String)
        }
    }

    /// 5 MB to match server-side cap.
    static let maxFileSize = 5 * 1024 * 1024

    var attachments: [Attachment] = []

    var anyUploading: Bool {
        attachments.contains { if case .uploading = $0.status { return true } else { return false } }
    }

    /// Paths of attachments that successfully uploaded. Order matches the order
    /// the user picked them in (most-recent appended last).
    var readyPaths: [String] {
        attachments.compactMap { att in
            if case .ready(let path) = att.status { return path }
            return nil
        }
    }

    enum UploadError: LocalizedError {
        case tooLarge(Int)
        var errorDescription: String? {
            switch self {
            case .tooLarge(let n): return "File too large: \(n) bytes (max \(AttachmentManager.maxFileSize))"
            }
        }
    }

    /// Adds an upload to the list and dispatches it over the WebSocket.
    /// Throws if the file exceeds the size cap; otherwise the upload is added
    /// in `.uploading` state and flips to `.ready` (or `.failed`) when the
    /// server replies.
    func startUpload(filename: String, data: Data, connection: ConnectionManager) throws -> UUID {
        guard data.count <= Self.maxFileSize else { throw UploadError.tooLarge(data.count) }
        let id = UUID()
        attachments.append(Attachment(id: id, filename: filename, status: .uploading))
        let base64 = data.base64EncodedString()
        connection.send(.uploadFile(uploadId: id, filename: filename, data: base64))
        return id
    }

    func remove(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func clear() {
        attachments.removeAll()
    }

    func handle(_ message: ServerMessage) {
        switch message {
        case .fileUploaded(let id, let path):
            update(id: id, status: .ready(path: path))
        case .fileUploadFailed(let id, let msg):
            update(id: id, status: .failed(msg))
        default: break
        }
    }

    private func update(id: UUID, status: Attachment.Status) {
        guard let idx = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[idx].status = status
    }
}
