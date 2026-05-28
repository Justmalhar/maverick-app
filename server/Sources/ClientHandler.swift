// server/Sources/ClientHandler.swift
import Foundation
import Network
import MaverickProtocol

final class ClientHandler: @unchecked Sendable {
    let id: UUID
    private let connection: NWConnection
    private let sessionManager: SessionManager
    private let uploadStore: UploadStore
    private let listingService: DirectoryListingService
    private let projectIndexer: ProjectIndexer
    private let gitWrapper: GitWrapper
    private var attachedSessionId: UUID?
    let onDisconnect: () -> Void

    init(
        id: UUID,
        connection: NWConnection,
        sessionManager: SessionManager,
        uploadStore: UploadStore,
        listingService: DirectoryListingService,
        projectIndexer: ProjectIndexer,
        gitWrapper: GitWrapper,
        onDisconnect: @escaping () -> Void
    ) {
        self.id = id
        self.connection = connection
        self.sessionManager = sessionManager
        self.uploadStore = uploadStore
        self.listingService = listingService
        self.projectIndexer = projectIndexer
        self.gitWrapper = gitWrapper
        self.onDisconnect = onDisconnect
    }

    func start() {
        connection.start(queue: .global())
        receive()
    }

    func disconnect() {
        if let sid = attachedSessionId {
            Task { await sessionManager.removeOutputObserver(sessionId: sid, clientId: id) }
        }
        connection.cancel()
    }

    private func receive() {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self else { return }
            if error != nil { self.handleDisconnect(); return }
            if let content,
               let msg = try? MaverickJSON.decoder().decode(ClientMessage.self, from: content) {
                Task { await self.handle(msg) }
            }
            self.receive()
        }
    }

    private func handle(_ message: ClientMessage) async {
        switch message {
        case .listSessions:
            send(.sessionList(sessions: await sessionManager.listSessions()))

        case .createSession(let name, let shell, let cwd):
            do {
                let info = try await sessionManager.createSession(name: name, shell: shell, cwd: cwd)
                send(.sessionCreated(session: info))
                send(.sessionList(sessions: await sessionManager.listSessions()))
                await attach(sessionId: info.id)
            } catch {
                send(.error(message: error.localizedDescription))
            }

        case .attachSession(let sessionId):
            await attach(sessionId: sessionId)

        case .input(let sessionId, let data):
            if let bytes = Data(base64Encoded: data) {
                await sessionManager.write(sessionId: sessionId, data: bytes)
            }

        case .resize(let sessionId, let cols, let rows):
            await sessionManager.resize(sessionId: sessionId, cols: UInt16(cols), rows: UInt16(rows))

        case .closeSession(let sessionId):
            await sessionManager.closeSession(id: sessionId)

        case .uploadFile(let uploadId, let filename, let data):
            do {
                let path = try uploadStore.save(filename: filename, base64Data: data)
                send(.fileUploaded(uploadId: uploadId, path: path))
            } catch {
                send(.fileUploadFailed(uploadId: uploadId, message: error.localizedDescription))
            }

        case .listDirectory(let requestId, let path):
            do {
                let result = try listingService.list(path: path)
                send(.directoryListing(requestId: requestId, path: result.path, entries: result.entries))
            } catch {
                send(.directoryListingFailed(requestId: requestId, message: error.localizedDescription))
            }

        case .indexProject(let requestId, let path, let refresh):
            projectIndexer.index(path: path, refresh: refresh) { [weak self] root, entries, complete in
                self?.send(.indexChunk(requestId: requestId, root: root, entries: entries, complete: complete))
            }

        case .gitStatus(let requestId, let path):
            do {
                let status = try gitWrapper.status(path: path)
                send(.gitStatusResult(requestId: requestId, status: status))
            } catch {
                send(.gitStatusFailed(requestId: requestId, message: error.localizedDescription))
            }

        case .gitDiff(let requestId, let path, let file, let staged):
            do {
                let result = try gitWrapper.diff(path: path, file: file, staged: staged)
                send(.gitDiffResult(requestId: requestId, file: file, diff: result.diff, truncated: result.truncated))
            } catch {
                send(.gitDiffFailed(requestId: requestId, message: error.localizedDescription))
            }

        case .createAgentSession:
            // Agent session creation is handled in Task 10 (AgentEventBroadcaster).
            send(.error(message: "Agent sessions not yet supported"))

        case .switchSessionMode:
            // Session mode switching is handled in Task 10.
            send(.error(message: "Session mode switching not yet supported"))

        case .agentInput:
            // Agent input forwarding is handled in Task 10.
            send(.error(message: "Agent input not yet supported"))

        case .permissionResponse(let sessionId, let requestId, let allowed):
            // Forward the permission decision to HookServer via the broadcast mechanism (Task 10).
            // For now, no-op — HookServer.resolvePermission will be wired in Task 10.
            _ = (sessionId, requestId, allowed)
        }
    }

    /// How much of the scrollback (in raw bytes) we replay to a freshly-attached
    /// client. 256 KB ≈ 4–8 thousand lines, base64-encodes to ~340 KB which
    /// stays comfortably under iOS's default WebSocket frame limit (1 MB).
    private static let scrollbackReplayCap = 256 * 1024

    private func attach(sessionId: UUID) async {
        if let prev = attachedSessionId {
            await sessionManager.removeOutputObserver(sessionId: prev, clientId: id)
        }
        attachedSessionId = sessionId
        if let sb = await sessionManager.getScrollback(sessionId: sessionId), !sb.isEmpty {
            let trimmed: Data
            if sb.count > Self.scrollbackReplayCap {
                trimmed = Data(sb.suffix(Self.scrollbackReplayCap))
            } else {
                trimmed = sb
            }
            send(.scrollback(sessionId: sessionId, data: trimmed.base64EncodedString()))
        }
        let cid = id
        await sessionManager.addOutputObserver(sessionId: sessionId, clientId: cid) { [weak self] data in
            self?.send(.output(sessionId: sessionId, data: data.base64EncodedString()))
        }
    }

    func send(_ message: ServerMessage) {
        guard let data = try? MaverickJSON.encoder().encode(message) else { return }
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let ctx = NWConnection.ContentContext(identifier: "ws", metadata: [meta])
        connection.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
    }

    private func handleDisconnect() {
        if let sid = attachedSessionId {
            Task { await sessionManager.removeOutputObserver(sessionId: sid, clientId: id) }
        }
        onDisconnect()
    }
}
