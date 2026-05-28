// client/Sources/Features/Connection/ConnectionManager.swift
import Foundation
import MaverickProtocol

@Observable
final class ConnectionManager: NSObject, URLSessionWebSocketDelegate {
    enum State: Equatable { case disconnected, connecting, connected }

    var state: State = .disconnected
    var lastError: String?
    var onMessage: ((ServerMessage) -> Void)?

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var reconnectWorkItem: DispatchWorkItem?
    private var host = ""
    private var port = 8765
    private var token = ""
    private(set) var delay: TimeInterval = 1

    /// We open a new task on each reconnect; this tag lets the delegate ignore
    /// late callbacks from cancelled tasks.
    private var activeTaskId = 0

    override init() {
        super.init()
    }

    // MARK: - Public

    func connect(host: String, port: Int = 8765, token: String = "") {
        self.host = host; self.port = port; self.token = token
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
        DispatchQueue.main.async { [weak self] in self?.state = .disconnected }
    }

    func send(_ message: ClientMessage) {
        guard let data = try? MaverickJSON.encoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
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

        // Fresh session per attempt so the delegate retains us cleanly.
        // Previous session is invalidated to break any retain cycle.
        session?.invalidateAndCancel()
        let config = URLSessionConfiguration.default
        // Tight handshake timeout — the user shouldn't sit on a dead socket
        // for 30s waiting for the OS default.
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let newSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        session = newSession

        activeTaskId &+= 1
        let myTaskId = activeTaskId
        let newTask = newSession.webSocketTask(with: url)
        // Default is 1 MB; scrollback replays for long-running sessions easily
        // exceed that. Bump to 16 MB so receives don't drop the connection.
        newTask.maximumMessageSize = 16 * 1024 * 1024
        // Stash the id on the task via its taskDescription so the delegate
        // can correlate late callbacks.
        newTask.taskDescription = String(myTaskId)
        task = newTask
        newTask.resume()
        readLoop(taskId: myTaskId)
    }

    private func readLoop(taskId: Int) {
        // Capture the task we're reading from to avoid racing against
        // reconnects that swap out `self.task`.
        let target = task
        target?.receive { [weak self] result in
            guard let self else { return }
            // If the task was replaced (reconnect) while we were awaiting,
            // drop the result silently.
            guard taskId == self.activeTaskId else { return }
            switch result {
            case .success(let msg):
                // Receiving means we're truly open; this is a belt-and-suspenders
                // signal in addition to the delegate's didOpen callback.
                DispatchQueue.main.async {
                    if self.state != .connected { self.state = .connected }
                    self.resetDelay()
                }
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let serverMsg = try? MaverickJSON.decoder().decode(ServerMessage.self, from: data) {
                    DispatchQueue.main.async { self.onMessage?(serverMsg) }
                }
                self.readLoop(taskId: taskId)
            case .failure(let err):
                self.lastError = err.localizedDescription
                self.scheduleReconnect()
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

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        guard let descId = webSocketTask.taskDescription, Int(descId) == activeTaskId else { return }
        DispatchQueue.main.async { [weak self] in
            self?.state = .connected
            self?.resetDelay()
        }
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        guard let descId = webSocketTask.taskDescription, Int(descId) == activeTaskId else { return }
        scheduleReconnect()
    }
}
