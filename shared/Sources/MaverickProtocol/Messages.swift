import Foundation

private enum MessageType: String, Codable {
    case listSessions = "list_sessions"
    case createSession = "create_session"
    case attachSession = "attach_session"
    case input, resize
    case closeSession = "close_session"
    case sessionList = "session_list"
    case sessionCreated = "session_created"
    case output, scrollback
    case sessionClosed = "session_closed"
    case error
}

public enum ClientMessage: Codable, Sendable {
    case listSessions
    case createSession(name: String, shell: String)
    case attachSession(sessionId: UUID)
    case input(sessionId: UUID, data: String)
    case resize(sessionId: UUID, cols: Int, rows: Int)
    case closeSession(sessionId: UUID)

    private enum CK: String, CodingKey { case type, name, shell, sessionId, data, cols, rows }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(MessageType.self, forKey: .type) {
        case .listSessions:  self = .listSessions
        case .createSession: self = .createSession(name: try c.decode(String.self, forKey: .name), shell: try c.decode(String.self, forKey: .shell))
        case .attachSession: self = .attachSession(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        case .input:         self = .input(sessionId: try c.decode(UUID.self, forKey: .sessionId), data: try c.decode(String.self, forKey: .data))
        case .resize:        self = .resize(sessionId: try c.decode(UUID.self, forKey: .sessionId), cols: try c.decode(Int.self, forKey: .cols), rows: try c.decode(Int.self, forKey: .rows))
        case .closeSession:  self = .closeSession(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unexpected client message type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .listSessions:
            try c.encode(MessageType.listSessions, forKey: .type)
        case .createSession(let n, let s):
            try c.encode(MessageType.createSession, forKey: .type); try c.encode(n, forKey: .name); try c.encode(s, forKey: .shell)
        case .attachSession(let id):
            try c.encode(MessageType.attachSession, forKey: .type); try c.encode(id, forKey: .sessionId)
        case .input(let id, let d):
            try c.encode(MessageType.input, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(d, forKey: .data)
        case .resize(let id, let cols, let rows):
            try c.encode(MessageType.resize, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(cols, forKey: .cols); try c.encode(rows, forKey: .rows)
        case .closeSession(let id):
            try c.encode(MessageType.closeSession, forKey: .type); try c.encode(id, forKey: .sessionId)
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

    private enum CK: String, CodingKey { case type, sessions, session, sessionId, data, message }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        switch try c.decode(MessageType.self, forKey: .type) {
        case .sessionList:    self = .sessionList(sessions: try c.decode([SessionInfo].self, forKey: .sessions))
        case .sessionCreated: self = .sessionCreated(session: try c.decode(SessionInfo.self, forKey: .session))
        case .output:         self = .output(sessionId: try c.decode(UUID.self, forKey: .sessionId), data: try c.decode(String.self, forKey: .data))
        case .scrollback:     self = .scrollback(sessionId: try c.decode(UUID.self, forKey: .sessionId), data: try c.decode(String.self, forKey: .data))
        case .sessionClosed:  self = .sessionClosed(sessionId: try c.decode(UUID.self, forKey: .sessionId))
        case .error:          self = .error(message: try c.decode(String.self, forKey: .message))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unexpected server message type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        switch self {
        case .sessionList(let s):
            try c.encode(MessageType.sessionList, forKey: .type); try c.encode(s, forKey: .sessions)
        case .sessionCreated(let s):
            try c.encode(MessageType.sessionCreated, forKey: .type); try c.encode(s, forKey: .session)
        case .output(let id, let d):
            try c.encode(MessageType.output, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(d, forKey: .data)
        case .scrollback(let id, let d):
            try c.encode(MessageType.scrollback, forKey: .type); try c.encode(id, forKey: .sessionId); try c.encode(d, forKey: .data)
        case .sessionClosed(let id):
            try c.encode(MessageType.sessionClosed, forKey: .type); try c.encode(id, forKey: .sessionId)
        case .error(let m):
            try c.encode(MessageType.error, forKey: .type); try c.encode(m, forKey: .message)
        }
    }
}
