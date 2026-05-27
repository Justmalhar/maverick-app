// server/Sources/UploadStore.swift
import Foundation

/// Server-side store for files uploaded by clients. Files are saved under
/// `/tmp/maverick-uploads/<uuid>-<sanitized-filename>` so coding agents can
/// reference them by path.
final class UploadStore: @unchecked Sendable {
    let directory: URL

    /// 5 MB cap per upload — keeps WebSocket frames manageable on iOS.
    static let maxFileSize = 5 * 1024 * 1024

    enum UploadError: LocalizedError {
        case invalidBase64
        case fileTooLarge(Int)
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidBase64: return "Invalid base64 payload."
            case .fileTooLarge(let n): return "File too large (\(n) bytes; max \(UploadStore.maxFileSize))."
            case .writeFailed(let msg): return "Write failed: \(msg)"
            }
        }
    }

    init() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("maverick-uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
    }

    /// Decodes the base64 payload, writes to a uniquely-named file, returns
    /// the absolute path on disk. Throws on invalid input.
    func save(filename: String, base64Data: String) throws -> String {
        guard let data = Data(base64Encoded: base64Data) else {
            throw UploadError.invalidBase64
        }
        guard data.count <= Self.maxFileSize else {
            throw UploadError.fileTooLarge(data.count)
        }
        let safeName = Self.sanitize(filename)
        let id = UUID().uuidString.lowercased()
        let url = directory.appendingPathComponent("\(id)-\(safeName)")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw UploadError.writeFailed(error.localizedDescription)
        }
        return url.path
    }

    /// Strips characters that could enable path traversal or shell mishaps.
    /// Keeps it readable so the agent can identify the file by name.
    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let cleaned = String(scalars)
        // Cap filename length so we don't blow past macOS's 255-byte path limit.
        return String(cleaned.prefix(120))
    }
}
