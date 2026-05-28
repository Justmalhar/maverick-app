// server/Sources/HookServer.swift
import Foundation
import Network
import MaverickProtocol

// MARK: - HookServer

/// Lightweight HTTP/1.1 server that receives Claude Code hook POSTs on localhost:7789.
///
/// - For PermissionRequest hooks the connection is held open (≤ 30 s) until
///   `resolvePermission(requestId:allowed:)` is called or the timeout fires.
/// - All other hooks are acknowledged immediately with `HTTP 200 {}`.
final class HookServer {

    // MARK: Public API

    /// Called for every non-permission AgentEvent.  Receives the event and the
    /// raw `session_id` string extracted from the hook payload (empty string if absent).
    var onEvent: ((AgentEvent, String) -> Void)? {
        get {
            propertiesLock.lock()
            defer { propertiesLock.unlock() }
            return _onEvent
        }
        set {
            propertiesLock.lock()
            defer { propertiesLock.unlock() }
            _onEvent = newValue
        }
    }

    // MARK: Private state

    private var listener: NWListener?

    var normalizer: AgentEventNormalizing? {
        get {
            propertiesLock.lock()
            defer { propertiesLock.unlock() }
            return _normalizer
        }
        set {
            propertiesLock.lock()
            defer { propertiesLock.unlock() }
            _normalizer = newValue
        }
    }

    // Thread-safe backing stores for normalizer and onEvent
    private var _normalizer: AgentEventNormalizing?
    private var _onEvent: ((AgentEvent, String) -> Void)?

    // Thread-safe locks
    private let propertiesLock = NSLock()

    // Pending PermissionRequest continuations keyed by requestId.
    private let pendingLock = NSLock()
    private var pendingPermissions: [String: CheckedContinuation<Bool, Never>] = [:]

    // MARK: Configuration

    func setNormalizer(_ normalizer: AgentEventNormalizing) {
        self.normalizer = normalizer  // Uses the thread-safe computed property
    }

    // MARK: Lifecycle

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let nwPort = NWEndpoint.Port(rawValue: 7789)!
        let l = try NWListener(using: params, on: nwPort)

        let ready = DispatchSemaphore(value: 0)

        l.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        l.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("[HookServer] Listening on localhost:7789")
                ready.signal()
            case .failed(let err):
                NSLog("[HookServer] Listener failed: %@", String(describing: err))
                ready.signal()
            default:
                break
            }
        }
        l.start(queue: .global())
        listener = l

        // Wait for listener to reach .ready or .failed state.
        ready.wait()
    }

    func stop() {
        listener?.cancel()
        listener = nil

        // Drain any pending permission continuations with deny.
        pendingLock.lock()
        let pending = pendingPermissions
        pendingPermissions.removeAll()
        pendingLock.unlock()

        for (_, cont) in pending {
            cont.resume(returning: false)
        }
    }

    /// Called by the WebSocket `ClientHandler` when the iOS client sends a
    /// permission response for a previously-forwarded PermissionRequest.
    func resolvePermission(requestId: String, allowed: Bool) {
        pendingLock.lock()
        let cont = pendingPermissions.removeValue(forKey: requestId)
        pendingLock.unlock()
        cont?.resume(returning: allowed)
    }

    // MARK: Connection handling

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global())
        receiveRequest(connection: connection)
    }

    private func receiveRequest(connection: NWConnection) {
        // Receive up to 64 KB — enough for any hook payload.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                NSLog("[HookServer] receive error: %@", String(describing: error))
                connection.cancel()
                return
            }

            guard let data, !data.isEmpty else {
                if isComplete { connection.cancel() }
                return
            }

            self.handleRawRequest(data, connection: connection)
        }
    }

    // MARK: HTTP parsing

    private func handleRawRequest(_ raw: Data, connection: NWConnection) {
        // Find \r\n\r\n separator between headers and body.
        guard let separatorRange = raw.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            // Might be a partial receive; for simplicity send 400 and close.
            sendBadRequest(connection)
            return
        }

        let headersData = raw[raw.startIndex..<separatorRange.lowerBound]
        let bodyStart = separatorRange.upperBound

        guard let headersString = String(data: headersData, encoding: .utf8) else {
            sendBadRequest(connection)
            return
        }

        // Extract Content-Length.
        var contentLength = 0
        for line in headersString.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        let bodyAvailable = raw.count - bodyStart
        if contentLength == 0 {
            // No body — nothing to do.
            sendOK(connection)
            return
        }

        if bodyAvailable >= contentLength {
            let bodyData = Data(raw[bodyStart..<(bodyStart + contentLength)])
            processBody(bodyData, connection: connection)
        } else {
            // Need more data. Read the remainder.
            let remaining = contentLength - bodyAvailable
            let partial = bodyAvailable > 0 ? Data(raw[bodyStart...]) : Data()
            receiveRemainingBody(partial, remaining: remaining, connection: connection)
        }
    }

    private func receiveRemainingBody(
        _ accumulated: Data,
        remaining: Int,
        connection: NWConnection
    ) {
        connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                NSLog("[HookServer] body receive error: %@", String(describing: error))
                connection.cancel()
                return
            }
            let body = accumulated + (data ?? Data())
            self.processBody(body, connection: connection)
        }
    }

    // MARK: Payload processing

    private func processBody(_ body: Data, connection: NWConnection) {
        guard
            let jsonObj = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            sendBadRequest(connection)
            return
        }

        let sessionId = jsonObj["session_id"] as? String ?? ""

        // Detect PermissionRequest via `hook_event_name` field.
        let hookEventName = jsonObj["hook_event_name"] as? String ?? ""

        if hookEventName == "PermissionRequest" {
            // Extract requestId — Claude Code uses "request_id" (snake_case).
            let requestId = jsonObj["request_id"] as? String ?? UUID().uuidString

            // Normalize to AgentEvent if a normalizer is registered.
            if let normalizer, let event = normalizer.normalize(hookPayload: jsonObj) {
                onEvent?(event, sessionId)
            }

            // Hold the connection open while we wait for the iOS client's decision.
            Task {
                let allowed = await self.waitForPermission(requestId: requestId)
                self.sendPermissionResponse(connection, allowed: allowed)
            }
        } else {
            // Non-blocking: normalize and fire, then immediately acknowledge.
            if let normalizer, let event = normalizer.normalize(hookPayload: jsonObj) {
                onEvent?(event, sessionId)
            }
            sendOK(connection)
        }
    }

    // MARK: Permission wait

    private func waitForPermission(requestId: String) async -> Bool {
        // Race a 30-second timeout against the iOS client's response.
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            pendingLock.lock()
            pendingPermissions[requestId] = continuation
            pendingLock.unlock()

            // Schedule auto-deny after 30 seconds.
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                guard let self else { return }
                self.pendingLock.lock()
                let cont = self.pendingPermissions.removeValue(forKey: requestId)
                self.pendingLock.unlock()
                if let cont {
                    NSLog("[HookServer] Permission request %@ timed out — auto-denying", requestId)
                    cont.resume(returning: false)
                }
            }
        }
    }

    // MARK: HTTP responses

    private func sendPermissionResponse(_ connection: NWConnection, allowed: Bool) {
        let behavior = allowed ? "allow" : "deny"
        let bodyString = """
        {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"\(behavior)"}}}
        """
        let bodyData = bodyString.data(using: .utf8)!
        let response =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: \(bodyData.count)\r\n" +
            "\r\n"
        let responseData = response.data(using: .utf8)! + bodyData
        sendAndClose(connection, data: responseData)
    }

    private func sendOK(_ connection: NWConnection) {
        let body = "{}"
        let response =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: 2\r\n" +
            "\r\n" +
            body
        sendAndClose(connection, data: response.data(using: .utf8)!)
    }

    private func sendBadRequest(_ connection: NWConnection) {
        let response =
            "HTTP/1.1 400 Bad Request\r\n" +
            "Content-Length: 0\r\n" +
            "\r\n"
        sendAndClose(connection, data: response.data(using: .utf8)!)
    }

    private func sendAndClose(_ connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
