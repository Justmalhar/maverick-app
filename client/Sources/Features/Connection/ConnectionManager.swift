// client/Sources/Features/Connection/ConnectionManager.swift
import Foundation
import MaverickProtocol

@Observable
final class ConnectionManager {
    enum State: Equatable { case disconnected, connecting, connected }

    var state: State = .disconnected
    var lastError: String?
    var onMessage: ((ServerMessage) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var reconnectWorkItem: DispatchWorkItem?
    private var host = ""
    private var port = 8765
    private var token = ""
    private(set) var delay: TimeInterval = 1

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
        state = .disconnected
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
        state = .connecting
        let urlStr = token.isEmpty
            ? "ws://\(host):\(port)/ws"
            : "ws://\(host):\(port)/ws?token=\(token)"
        guard let url = URL(string: urlStr) else { state = .disconnected; return }
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: url)
        task?.resume()
        // URLSessionWebSocketTask doesn't expose a "connected" callback without
        // a delegate, so mark connected optimistically right after resume.
        // If the handshake actually fails, readLoop's failure branch will
        // reset state and trigger reconnect with backoff.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.state == .connecting { self.state = .connected }
        }
        readLoop()
    }

    private func readLoop() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                self.state = .connected
                self.resetDelay()
                if case .string(let text) = msg,
                   let data = text.data(using: .utf8),
                   let serverMsg = try? MaverickJSON.decoder().decode(ServerMessage.self, from: data) {
                    DispatchQueue.main.async { self.onMessage?(serverMsg) }
                }
                self.readLoop()
            case .failure(let err):
                self.lastError = err.localizedDescription
                self.scheduleReconnect()
            }
        }
    }

    private func scheduleReconnect() {
        state = .disconnected
        let d = delay
        recordFailure()
        let item = DispatchWorkItem { [weak self] in self?.openSocket() }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + d, execute: item)
    }
}
