// client/Sources/Features/Connection/ConnectionManager.swift
import Foundation
import MaverickProtocol

/// Pure Swift @Observable so it plays nicely with SwiftUI. The actual
/// URLSessionWebSocketDelegate lives in a tiny NSObject helper class below —
/// mixing @Observable + NSObject in the same type triggers a refcount crash
/// during deinit on the simulator.
@Observable
final class ConnectionManager {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        /// A paired (Noise) connection dropped. The single-use pairing token is
        /// spent, so we cannot transparently reconnect — the user must re-pair
        /// (scan a fresh QR). Seamless reconnect is deferred to M1.5.
        case rePairRequired
    }

    var state: State = .disconnected
    var lastError: String?
    var onMessage: ((ServerMessage) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var delegateBox: SocketDelegateBox?
    private var reconnectWorkItem: DispatchWorkItem?
    private var host = ""
    private var port = 8765
    private var token = ""
    private(set) var delay: TimeInterval = 1

    /// Wire codec. Plaintext for loopback/dev (default), Noise for paired
    /// sessions (installed by `connectPaired`). Every `send`/receive routes
    /// through this so call sites never change.
    private var transport: Transport = PlaintextTransport()

    /// `true` once `connectPaired` adopts an encrypted socket. Paired sessions
    /// do NOT use the plaintext backoff/reconnect loop (their token is single-use).
    private var isPaired = false

    /// Monotonic id used to ignore late callbacks from cancelled tasks.
    private var activeTaskId = 0

    // MARK: - Public

    func connect(host: String, port: Int = 8765, token: String = "") {
        self.host = host; self.port = port; self.token = token
        self.transport = PlaintextTransport()
        self.isPaired = false
        UserDefaults.standard.set(host, forKey: "lastHost")
        UserDefaults.standard.set(port, forKey: "lastPort")
        openSocket()
    }

    func disconnect() {
        reconnectWorkItem?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        session = nil
        task = nil
        delegateBox = nil
        isPaired = false
        transport = PlaintextTransport()
        DispatchQueue.main.async { [weak self] in self?.state = .disconnected }
    }

    func send(_ message: ClientMessage) {
        guard let wire = try? transport.encode(message) else { return }
        task?.send(wire) { _ in }
    }

    // MARK: - Backoff helpers (internal for tests)

    func nextDelay() -> TimeInterval { delay }
    func recordFailure() { delay = min(delay * 2, 30) }
    func resetDelay() { delay = 1 }

    // MARK: - Private

    private func openSocket() {
        DispatchQueue.main.async { [weak self] in self?.state = .connecting }
        let urlStr = token.isEmpty
            ? "ws://\(host):\(port)/ws"
            : "ws://\(host):\(port)/ws?token=\(token)"
        guard let url = URL(string: urlStr) else {
            DispatchQueue.main.async { [weak self] in self?.state = .disconnected }
            return
        }

        // Tear down any previous session/delegate first so we don't accumulate
        // delegate retain cycles or stray callbacks from old tasks.
        session?.invalidateAndCancel()
        session = nil
        delegateBox = nil

        activeTaskId &+= 1
        let myTaskId = activeTaskId

        let box = SocketDelegateBox(
            taskId: myTaskId,
            onOpen: { [weak self] in self?.handleOpen(taskId: myTaskId) },
            onClose: { [weak self] in self?.handleClose(taskId: myTaskId) }
        )
        delegateBox = box

        let config = URLSessionConfiguration.default
        // Tight handshake timeout — the user shouldn't sit on a dead socket
        // for 30s waiting for the OS default.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let newSession = URLSession(configuration: config, delegate: box, delegateQueue: nil)
        session = newSession

        let newTask = newSession.webSocketTask(with: url)
        // Default is 1 MB; scrollback replays for long-running sessions easily
        // exceed that. Bump to 16 MB so receives don't drop the connection.
        newTask.maximumMessageSize = 16 * 1024 * 1024
        newTask.taskDescription = String(myTaskId)
        task = newTask
        newTask.resume()
        readLoop(taskId: myTaskId)
    }

    fileprivate func handleOpen(taskId: Int) {
        guard taskId == activeTaskId else { return }
        DispatchQueue.main.async { [weak self] in
            self?.state = .connected
            self?.resetDelay()
        }
    }

    fileprivate func handleClose(taskId: Int) {
        guard taskId == activeTaskId else { return }
        handleDrop()
    }

    /// Unified drop handler. Plaintext sessions back off and reconnect; paired
    /// (Noise) sessions cannot — their token is single-use — so they surface
    /// `rePairRequired` and stop (seamless reconnect is M1.5).
    private func handleDrop() {
        if isPaired {
            task = nil
            DispatchQueue.main.async { [weak self] in self?.state = .rePairRequired }
            return
        }
        scheduleReconnect()
    }

    private func readLoop(taskId: Int) {
        let target = task
        target?.receive { [weak self] result in
            guard let self else { return }
            guard taskId == self.activeTaskId else { return }
            switch result {
            case .success(let msg):
                // Receiving means we're truly open — safety net in case the
                // delegate's didOpen didn't fire for some reason.
                DispatchQueue.main.async {
                    if self.state != .connected { self.state = .connected }
                    self.resetDelay()
                }
                // A decrypt/transport failure on a paired socket is fatal — the
                // counter is now out of sync, so surface it and stop. A `nil`
                // result is just an unrecognized-but-valid frame; keep reading.
                do {
                    if let serverMsg = try self.transport.decode(msg) {
                        DispatchQueue.main.async { self.onMessage?(serverMsg) }
                    }
                } catch {
                    self.lastError = error.localizedDescription
                    self.handleDrop()
                    return
                }
                self.readLoop(taskId: taskId)
            case .failure(let err):
                self.lastError = err.localizedDescription
                self.handleDrop()
            }
        }
    }

    private func scheduleReconnect() {
        let d = delay
        recordFailure()
        DispatchQueue.main.async { [weak self] in self?.state = .disconnected }
        let item = DispatchWorkItem { [weak self] in self?.openSocket() }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: item)
    }
}

// MARK: - Tiny NSObject delegate

private final class SocketDelegateBox: NSObject, URLSessionWebSocketDelegate {
    let taskId: Int
    let onOpen: () -> Void
    let onClose: () -> Void

    init(taskId: Int, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.taskId = taskId
        self.onOpen = onOpen
        self.onClose = onClose
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        onOpen()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        onClose()
    }
}
