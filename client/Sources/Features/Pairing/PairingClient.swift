// client/Sources/Features/Pairing/PairingClient.swift
import Foundation
import CryptoKit
import MaverickNoise

/// Outcome of a successful `/pair` Noise-XX handshake.
///
/// `webSocketTask` is the SAME socket the handshake ran over and is still open;
/// `ConnectionManager.connectPaired` adopts it as the live session transport.
/// Callers MUST NOT cancel/resume it.
struct PairingResult {
    /// Post-handshake encrypted transport (initiator: send=k1, recv=k2).
    let transport: NoiseTransport
    /// Daemon static public key (`rs`), proven == QR `k` during the handshake.
    let daemonStaticKey: Data
    /// Five-group safety number derived from the daemon static key, for the
    /// user-facing out-of-band verification step.
    let safetyNumber: String
    /// `base64url(SHA256(client_static_pub))` — the device id the daemon TOFU-pins.
    let deviceId: String
    /// The live, handshaken socket — reused by `ConnectionManager`, not closed here.
    let webSocketTask: URLSessionWebSocketTask
}

/// Typed pairing failures surfaced to the UI/state machine.
enum PairingClientError: Error, Equatable {
    /// Daemon closed the WS with a code (4401 = token/TOFU/Noise/path failure),
    /// optionally with a reason string.
    case closed(code: Int, reason: String?)
    /// A WS frame arrived in an unexpected form (e.g. neither text nor data).
    case unexpectedFrame
    /// The socket closed/failed before the handshake completed.
    case transportFailure(String)
}

/// Drives the daemon's `/pair` Noise-XX handshake as the initiator.
///
/// All frames are WebSocket TEXT frames carrying base64url of the raw Noise
/// bytes (the daemon is the wire authority). On success the underlying socket is
/// handed to `ConnectionManager` unchanged.
final class PairingClient {
    private let session: URLSession

    /// Inject a `URLSession` for testing; defaults to a tightly-timed ephemeral
    /// session so a dead daemon doesn't hang the pairing flow.
    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }

    func pair(
        payload: QRPayload,
        clientStatic: Curve25519.KeyAgreement.PrivateKey
    ) async throws -> PairingResult {
        guard let url = URL(string: "ws://\(payload.host):\(payload.port)/pair") else {
            throw PairingClientError.transportFailure("invalid rendezvous URL")
        }

        let task = session.webSocketTask(with: url)
        // Match the daemon's 16 MiB cap so post-handshake scrollback replays fit.
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()

        do {
            var hs = HandshakeStateInitiator(staticKey: clientStatic)

            // -> e, token
            let msg1 = try hs.writeMsg1(token: payload.token)
            try await send(task, bytes: msg1)

            // <- e, ee, s, es
            let msg2 = try await receive(task)
            let rs = try hs.readMsg2(msg2)

            // TOFU/QR pin: the responder static MUST equal the QR `k`.
            // Just throw — the single cancellation is owned by the outer `catch`
            // (which closes the socket with 4401 for this specific error, so we
            // don't double-cancel and overwrite `task.closeCode`).
            guard rs == payload.staticKey else {
                throw NoiseError.responderKeyMismatch
            }

            // -> s, se
            let msg3 = try hs.writeMsg3()
            try await send(task, bytes: msg3)

            let (sendKey, recvKey) = try hs.split()
            let transport = NoiseTransport(send: sendKey, recv: recvKey)

            return PairingResult(
                transport: transport,
                daemonStaticKey: rs,
                safetyNumber: Fingerprint.safetyNumber(rs),
                deviceId: Fingerprint.deviceId(clientStatic.publicKey.rawRepresentation),
                webSocketTask: task
            )
        } catch {
            // On any failure before completion, tear down the socket and map the
            // failure to a typed pairing error where useful. This is the SINGLE
            // cancellation point for the handshake socket — a responder-key
            // mismatch carries the daemon's bad-pin close code (4401); everything
            // else closes normally.
            let mapped = Self.mapFailure(error, task: task)
            let closeCode: URLSessionWebSocketTask.CloseCode =
                (error as? NoiseError) == .responderKeyMismatch
                    ? (.init(rawValue: 4401) ?? .normalClosure)
                    : .normalClosure
            task.cancel(with: closeCode, reason: nil)
            throw mapped
        }
    }

    // MARK: - Frame helpers

    /// Send raw Noise bytes as a base64url TEXT frame.
    private func send(_ task: URLSessionWebSocketTask, bytes: Data) async throws {
        try await task.send(.string(Base64URL.encode(bytes)))
    }

    /// Receive one frame and decode its base64url payload to raw Noise bytes.
    /// Daemon uses TEXT; `.data` is handled defensively.
    private func receive(_ task: URLSessionWebSocketTask) async throws -> Data {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return try Base64URL.decode(text)
        case .data(let data):
            guard let text = String(data: data, encoding: .utf8) else {
                throw PairingClientError.unexpectedFrame
            }
            return try Base64URL.decode(text)
        @unknown default:
            throw PairingClientError.unexpectedFrame
        }
    }

    /// Map a thrown error to a `PairingClientError`, attaching the WS close code
    /// (e.g. 4401) when the daemon closed the connection.
    private static func mapFailure(_ error: Error, task: URLSessionWebSocketTask) -> Error {
        // Already typed — keep it.
        if error is PairingClientError || error is NoiseError { return error }

        let code = task.closeCode.rawValue
        if code != 0, task.closeCode != .normalClosure {
            let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
            return PairingClientError.closed(code: code, reason: reason)
        }
        return PairingClientError.transportFailure(error.localizedDescription)
    }
}
