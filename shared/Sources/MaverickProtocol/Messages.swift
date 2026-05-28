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
    case listDirectory = "list_directory"
    case indexProject = "index_project"
    case gitStatus = "git_status"
    case gitDiff = "git_diff"
    case createAgentSession = "create_agent_session"
    case switchSessionMode = "switch_session_mode"
    case agentInput = "agent_input"
    case permissionResponse = "permission_response"
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
    case directoryListing = "directory_listing"
    case directoryListingFailed = "directory_listing_failed"
    case indexChunk = "index_chunk"
    case indexFailed = "index_failed"
    case gitStatusResult = "git_status_result"
    case gitStatusFailed = "git_status_failed"
    case gitDiffResult = "git_diff_result"
    case gitDiffFailed = "git_diff_failed"
    case agentEvent = "agent_event"
    case agentSessionCreated = "agent_session_created"
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

    /// Request a directory listing for the folder picker UI. `path` may be
    /// nil (home), `~`, `~/foo`, or an absolute path.
    case listDirectory(requestId: UUID, path: String?)

    /// Walk a project directory and stream entries back in chunks. `refresh`
    /// bypasses any cached index for this path.
    case indexProject(requestId: UUID, path: String, refresh: Bool)

    /// Run `git status` for the given path.
    case gitStatus(requestId: UUID, path: String)

    /// Run `git diff` for a single file inside the given repo. `staged=true`
    /// produces `git diff --cached`.
    case gitDiff(requestId: UUID, path: String, file: String, staged: Bool)

    /// Create a new agent session backed by a coding agent (not a raw PTY).
    case createAgentSession(name: String, provider: AgentProvider, cwd: String?)

    /// Switch an existing session between terminal and chat mode.
    case switchSessionMode(sessionId: UUID, mode: SessionMode)

    /// Send a chat message to an agent session.
    case agentInput(sessionId: UUID, text: String)

    /// Respond to a permission prompt from the agent.
    case permissionResponse(sessionId: UUID, requestId: UUID, allowed: Bool)

    private enum ClientCodingKeys: String, CodingKey {
        case type, name, shell, sessionId, data, cols, rows, uploadId, filename, cwd, requestId, path, refresh, file, staged
        case provider, mode, text, allowed
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
        case .listDirectory:
            self = .listDirectory(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                path: try container.decodeIfPresent(String.self, forKey: .path)
            )
        case .indexProject:
            self = .indexProject(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                path: try container.decode(String.self, forKey: .path),
                refresh: try container.decodeIfPresent(Bool.self, forKey: .refresh) ?? false
            )
        case .gitStatus:
            self = .gitStatus(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                path: try container.decode(String.self, forKey: .path)
            )
        case .gitDiff:
            self = .gitDiff(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                path: try container.decode(String.self, forKey: .path),
                file: try container.decode(String.self, forKey: .file),
                staged: try container.decodeIfPresent(Bool.self, forKey: .staged) ?? false
            )
        case .createAgentSession:
            self = .createAgentSession(
                name: try container.decode(String.self, forKey: .name),
                provider: try container.decode(AgentProvider.self, forKey: .provider),
                cwd: try container.decodeIfPresent(String.self, forKey: .cwd)
            )
        case .switchSessionMode:
            self = .switchSessionMode(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                mode: try container.decode(SessionMode.self, forKey: .mode)
            )
        case .agentInput:
            self = .agentInput(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                text: try container.decode(String.self, forKey: .text)
            )
        case .permissionResponse:
            self = .permissionResponse(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                requestId: try container.decode(UUID.self, forKey: .requestId),
                allowed: try container.decode(Bool.self, forKey: .allowed)
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
        case .listDirectory(let requestId, let path):
            try container.encode(ClientMessageType.listDirectory, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encodeIfPresent(path, forKey: .path)
        case .indexProject(let requestId, let path, let refresh):
            try container.encode(ClientMessageType.indexProject, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(path, forKey: .path)
            try container.encode(refresh, forKey: .refresh)
        case .gitStatus(let requestId, let path):
            try container.encode(ClientMessageType.gitStatus, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(path, forKey: .path)
        case .gitDiff(let requestId, let path, let file, let staged):
            try container.encode(ClientMessageType.gitDiff, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(path, forKey: .path)
            try container.encode(file, forKey: .file)
            try container.encode(staged, forKey: .staged)
        case .createAgentSession(let name, let provider, let cwd):
            try container.encode(ClientMessageType.createAgentSession, forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(provider, forKey: .provider)
            try container.encodeIfPresent(cwd, forKey: .cwd)
        case .switchSessionMode(let sessionId, let mode):
            try container.encode(ClientMessageType.switchSessionMode, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(mode, forKey: .mode)
        case .agentInput(let sessionId, let text):
            try container.encode(ClientMessageType.agentInput, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(text, forKey: .text)
        case .permissionResponse(let sessionId, let requestId, let allowed):
            try container.encode(ClientMessageType.permissionResponse, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(allowed, forKey: .allowed)
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
    case directoryListing(requestId: UUID, path: String, entries: [DirectoryEntry])
    case directoryListingFailed(requestId: UUID, message: String)

    /// Streamed chunk of project index entries. `complete=true` on the final chunk.
    case indexChunk(requestId: UUID, root: String, entries: [IndexEntry], complete: Bool)
    case indexFailed(requestId: UUID, message: String)

    case gitStatusResult(requestId: UUID, status: GitStatus)
    case gitStatusFailed(requestId: UUID, message: String)

    case gitDiffResult(requestId: UUID, file: String, diff: String, truncated: Bool)
    case gitDiffFailed(requestId: UUID, message: String)

    /// A normalized agent lifecycle event emitted by the coding agent backend.
    case agentEvent(sessionId: UUID, event: AgentEvent)

    /// Confirmation that an agent session was created.
    case agentSessionCreated(session: SessionInfo)

    private enum ServerCodingKeys: String, CodingKey {
        case type, sessions, session, sessionId, data, message, uploadId, path, requestId, entries
        case root, complete, status, file, diff, truncated
        case event
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
        case .directoryListing:
            self = .directoryListing(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                path: try container.decode(String.self, forKey: .path),
                entries: try container.decode([DirectoryEntry].self, forKey: .entries)
            )
        case .directoryListingFailed:
            self = .directoryListingFailed(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                message: try container.decode(String.self, forKey: .message)
            )
        case .indexChunk:
            self = .indexChunk(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                root: try container.decode(String.self, forKey: .root),
                entries: try container.decode([IndexEntry].self, forKey: .entries),
                complete: try container.decodeIfPresent(Bool.self, forKey: .complete) ?? false
            )
        case .indexFailed:
            self = .indexFailed(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                message: try container.decode(String.self, forKey: .message)
            )
        case .gitStatusResult:
            self = .gitStatusResult(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                status: try container.decode(GitStatus.self, forKey: .status)
            )
        case .gitStatusFailed:
            self = .gitStatusFailed(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                message: try container.decode(String.self, forKey: .message)
            )
        case .gitDiffResult:
            self = .gitDiffResult(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                file: try container.decode(String.self, forKey: .file),
                diff: try container.decode(String.self, forKey: .diff),
                truncated: try container.decodeIfPresent(Bool.self, forKey: .truncated) ?? false
            )
        case .gitDiffFailed:
            self = .gitDiffFailed(
                requestId: try container.decode(UUID.self, forKey: .requestId),
                message: try container.decode(String.self, forKey: .message)
            )
        case .agentEvent:
            self = .agentEvent(
                sessionId: try container.decode(UUID.self, forKey: .sessionId),
                event: try container.decode(AgentEvent.self, forKey: .event)
            )
        case .agentSessionCreated:
            self = .agentSessionCreated(session: try container.decode(SessionInfo.self, forKey: .session))
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
        case .directoryListing(let requestId, let path, let entries):
            try container.encode(ServerMessageType.directoryListing, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(path, forKey: .path)
            try container.encode(entries, forKey: .entries)
        case .directoryListingFailed(let requestId, let message):
            try container.encode(ServerMessageType.directoryListingFailed, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(message, forKey: .message)
        case .indexChunk(let requestId, let root, let entries, let complete):
            try container.encode(ServerMessageType.indexChunk, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(root, forKey: .root)
            try container.encode(entries, forKey: .entries)
            try container.encode(complete, forKey: .complete)
        case .indexFailed(let requestId, let message):
            try container.encode(ServerMessageType.indexFailed, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(message, forKey: .message)
        case .gitStatusResult(let requestId, let status):
            try container.encode(ServerMessageType.gitStatusResult, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(status, forKey: .status)
        case .gitStatusFailed(let requestId, let message):
            try container.encode(ServerMessageType.gitStatusFailed, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(message, forKey: .message)
        case .gitDiffResult(let requestId, let file, let diff, let truncated):
            try container.encode(ServerMessageType.gitDiffResult, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(file, forKey: .file)
            try container.encode(diff, forKey: .diff)
            try container.encode(truncated, forKey: .truncated)
        case .gitDiffFailed(let requestId, let message):
            try container.encode(ServerMessageType.gitDiffFailed, forKey: .type)
            try container.encode(requestId, forKey: .requestId)
            try container.encode(message, forKey: .message)
        case .agentEvent(let sessionId, let event):
            try container.encode(ServerMessageType.agentEvent, forKey: .type)
            try container.encode(sessionId, forKey: .sessionId)
            try container.encode(event, forKey: .event)
        case .agentSessionCreated(let session):
            try container.encode(ServerMessageType.agentSessionCreated, forKey: .type)
            try container.encode(session, forKey: .session)
        }
    }
}
