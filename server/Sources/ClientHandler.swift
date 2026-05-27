// server/Sources/ClientHandler.swift
import Foundation
import Network
import MaverickProtocol

final class ClientHandler: @unchecked Sendable {
    let id: UUID
    private let connection: NWConnection
    private let sessionManager: SessionManager
    private var attachedSessionId: UUID?
    let onDisconnect: () -> Void

    init(id: UUID, connection: NWConnection, sessionManager: SessionManager, onDisconnect: @escaping () -> Void) {
        self.id = id
        self.connection = connection
        self.sessionManager = sessionManager
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

        case .createSession(let name, let shell):
            do {
                let info = try await sessionManager.createSession(name: name, shell: shell)
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
