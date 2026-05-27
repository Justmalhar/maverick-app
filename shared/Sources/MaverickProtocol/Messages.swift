// shared/Sources/MaverickProtocol/Messages.swift
import Foundation

private enum ClientMessageType: String, Codable {
    case listSessions = "list_sessions"
    case createSession = "create_session"
    case attachSession = "attach_session"
    case input
    case resize
    case closeSession = "close_session"
    case uploadFile = "upload_file"
}

private enum ServerMessageType: String, Codable {
    case sessionList = "session_list"
    case sessionCreated = "session_created"
    case output
    case scrollback
    case sessionClosed = "session_closed"
    case error
    case fileUploaded = "file_uploaded"
    case fileUploadFailed = "file_upload_failed"
}

public enum ClientMessage: Codable, Sendable {
    case listSessions
    /// `cwd` is the absolute path on the Mac to start the shell in. If nil or
    /// empty, the server defaults to the user's home directory.
    case createSession(name: String, shell: String, cwd: String?)
    case attachSession(sessionId: UUID)
    case input(sessionId: UUID, data: String)
    case resize(sessionId: UUID, cols: Int, rows: Int)
    case closeSession(sessionId: UUID)
    /// Upload a file to the Mac's local /tmp so coding agents can reference it.
    /// `data` is base64-encoded file bytes. Server replies with .fileUploaded.
    case uploadFile(uploadId: UUID, filename: String, data: String)

    private enum ClientCodingKeys: String, CodingKey {
        case type, name, shell, sessionId, data, cols, rows, uploadId, filename, cwd
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ClientCodingKeys.self)
        let type = try container.decode(ClientMessageType.self, forKey: .type)
        switch type {
        case .listSessions:
            self = .listSessions
        case .createSession:
            self = .createSession(
                name: try container.decode(String.self, forKey: .name),
                shell: try container.decode(String.self, forKey: .shell),
                cwd: try container.decodeIfPresent(String.self, forKey: .cwd)
            )
        case .attachSession:
            self = .attachSession(sessionId: try container.decode(UUID.self, forKey: .sessionId))
        case .input:
            self = .input(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                data: try container.decode(String.self, forKey: .data)
            )
        case .resize:
            self = .resize(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                cols: try container.decode(Int.self, forKey: .cols),
                rows: try container.decode(Int.self, forKey: .rows)
            )
        case .closeSession:
            self = .closeSession(sessionId: try container.decode(UUID.self, forKey: .sessionId))
        case .uploadFile:
            self = .uploadFile(
                uploadId: try container.decode(UUID.self, forKey: .uploadId),
                filename: try container.decode(String.self, forKey: .filename),
                data: try container.decode(String.self, forKey: .data)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ClientCodingKeys.self)
        switch self {
        case .listSessions:
            try container.encode(ClientMessageType.listSessions, forKey: .type)
        case .createSession(let name, let shell, let cwd):
            try container.encode(ClientMessageType.createSession, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(shell, forKey: .shell)
            try container.encodeIfPresent(cwd, forKey: .cwd)
        case .attachSession(let sessionId):
            try container.encode(ClientMessageType.attachSession, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .input(let sessionId, let data):
            try container.encode(ClientMessageType.input, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(data, forKey: .data)
        case .resize(let sessionId, let cols, let rows):
            try container.encode(ClientMessageType.resize, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(cols, forKey: .cols)
            try container.encode(rows, forKey: .rows)
        case .closeSession(let sessionId):
            try container.encode(ClientMessageType.closeSession, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .uploadFile(let uploadId, let filename, let data):
            try container.encode(ClientMessageType.uploadFile, forKey: .type)
            try container.encode(uploadId, forKey: .uploadId)
            try container.encode(filename, forKey: .filename)
            try container.encode(data, forKey: .data)
        }
    }
}

public enum ServerMessage: Codable, Sendable {
    case sessionList(sessions: [SessionInfo])
    case sessionCreated(session: SessionInfo)
    case output(sessionId: UUID, data: String)
    case scrollback(sessionId: UUID, data: String)
    case sessionClosed(sessionId: UUID)
    case error(message: String)
    case fileUploaded(uploadId: UUID, path: String)
    case fileUploadFailed(uploadId: UUID, message: String)

    private enum ServerCodingKeys: String, CodingKey {
        case type, sessions, session, sessionId, data, message, uploadId, path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ServerCodingKeys.self)
        let type = try container.decode(ServerMessageType.self, forKey: .type)
        switch type {
        case .sessionList:
            self = .sessionList(sessions: try container.decode([SessionInfo].self, forKey: .sessions))
        case .sessionCreated:
            self = .sessionCreated(session: try container.decode(SessionInfo.self, forKey: .session))
        case .output:
            self = .output(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                data: try container.decode(String.self, forKey: .data)
            )
        case .scrollback:
            self = .scrollback(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                data: try container.decode(String.self, forKey: .data)
            )
        case .sessionClosed:
            self = .sessionClosed(sessionId: try container.decode(UUID.self, forKey: .sessionId))
        case .error:
            self = .error(message: try container.decode(String.self, forKey: .message))
        case .fileUploaded:
            self = .fileUploaded(
                uploadId: try container.decode(UUID.self, forKey: .uploadId),
                path: try container.decode(String.self, forKey: .path)
            )
        case .fileUploadFailed:
            self = .fileUploadFailed(
                uploadId: try container.decode(UUID.self, forKey: .uploadId),
                message: try container.decode(String.self, forKey: .message)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ServerCodingKeys.self)
        switch self {
        case .sessionList(let sessions):
            try container.encode(ServerMessageType.sessionList, forKey: .type)
            try container.encode(sessions, forKey: .sessions)
        case .sessionCreated(let session):
            try container.encode(ServerMessageType.sessionCreated, forKey: .type)
            try container.encode(session, forKey: .session)
        case .output(let sessionId, let data):
            try container.encode(ServerMessageType.output, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(data, forKey: .data)
        case .scrollback(let sessionId, let data):
            try container.encode(ServerMessageType.scrollback, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(data, forKey: .data)
        case .sessionClosed(let sessionId):
            try container.encode(ServerMessageType.sessionClosed, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
        case .error(let message):
            try container.encode(ServerMessageType.error, forKey: .type)
            try container.encode(message, forKey: .message)
        case .fileUploaded(let uploadId, let path):
            try container.encode(ServerMessageType.fileUploaded, forKey: .type)
            try container.encode(uploadId, forKey: .uploadId)
            try container.encode(path, forKey: .path)
        case .fileUploadFailed(let uploadId, let message):
            try container.encode(ServerMessageType.fileUploadFailed, forKey: .type)
            try container.encode(uploadId, forKey: .uploadId)
            try container.encode(message, forKey: .message)
        }
    }
}
