// server/Sources/WebSocketServer.swift
import Foundation
import Network
import MaverickProtocol

final class WebSocketServer {
    private var listener: NWListener?
    private var clients: [UUID: ClientHandler] = [:]
    private let clientsLock = NSLock()
    private let sessionManager: SessionManager
    private let uploadStore = UploadStore()
    private let listingService = DirectoryListingService()
    private let projectIndexer = ProjectIndexer()
    private let gitWrapper = GitWrapper()
    private let port: UInt16

    var actualPort: UInt16? { listener?.port?.rawValue }

    init(sessionManager: SessionManager, port: UInt16 = 8765) {
        self.sessionManager = sessionManager
        self.port = port
    }

    /// Broadcast a normalized agent event to all connected clients.
    func broadcastAgentEvent(sessionId: UUID, event: AgentEvent) {
        clientsLock.lock()
        let snapshot = Array(clients.values)
        clientsLock.unlock()
        snapshot.forEach { $0.send(.agentEvent(sessionId: sessionId, event: event)) }
    }

    /// Inject the HookServer reference into all currently-connected (and future) ClientHandlers.
    func setHookServer(_ hookServer: HookServer) {
        clientsLock.lock()
        let snapshot = Array(clients.values)
        clientsLock.unlock()
        snapshot.forEach { $0.setHookServer(hookServer) }
        // Store for future connections
        pendingHookServer = hookServer
    }

    private var pendingHookServer: HookServer?

    func start() throws {
        let params = NWParameters.tcp
        let wsOpts = NWProtocolWebSocket.Options()
        wsOpts.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOpts, at: 0)

        let nwPort = port == 0 ? NWEndpoint.Port.any : NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener?.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                NSLog("[MaverickAgent] listener failed: %@", String(describing: err))
            }
        }
        listener?.start(queue: .global())

        // Give listener a moment to bind
        Thread.sleep(forTimeInterval: 0.1)

        // Wire session-closed broadcast to all clients
        Task { [weak self] in
            await self?.sessionManager.setClosedHandler { [weak self] id in
                self?.broadcastSessionClosed(id)
            }
        }
    }

    func stop() {
        listener?.cancel()
        clientsLock.lock()
        let snapshot = Array(clients.values)
        clients.removeAll()
        clientsLock.unlock()
        snapshot.forEach { $0.disconnect() }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let handler = ClientHandler(
            id: id,
            connection: connection,
            sessionManager: sessionManager,
            uploadStore: uploadStore,
            listingService: listingService,
            projectIndexer: projectIndexer,
            gitWrapper: gitWrapper,
            onDisconnect: { [weak self] in self?.removeClient(id: id) }
        )
        if let hookServer = pendingHookServer {
            handler.setHookServer(hookServer)
        }
        clientsLock.lock()
        clients[id] = handler
        clientsLock.unlock()
        handler.start()
    }

    private func removeClient(id: UUID) {
        clientsLock.lock()
        clients.removeValue(forKey: id)
        clientsLock.unlock()
    }

    private func broadcastSessionClosed(_ sessionId: UUID) {
        clientsLock.lock()
        let snapshot = Array(clients.values)
        clientsLock.unlock()
        snapshot.forEach { $0.send(.sessionClosed(sessionId: sessionId)) }
    }
}
