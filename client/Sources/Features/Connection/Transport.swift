// client/Sources/Features/Connection/Transport.swift
import Foundation
import MaverickProtocol
import MaverickNoise

/// Pluggable wire codec for `ConnectionManager`. Each transport owns the
/// translation between a `ClientMessage`/`ServerMessage` and the raw
/// `URLSessionWebSocketTask.Message` that travels over the socket.
///
/// Two implementations exist:
/// - `PlaintextTransport` — today's loopback/dev behavior (JSON in a text frame).
/// - `NoiseTransportAdapter` — paired sessions; Noise-encrypted, base64url text.
///
/// `decode` returns an optional `ServerMessage`: a frame that is structurally
/// valid for the transport but does not decode to a known `ServerMessage`
/// yields `nil` (mirrors the previous best-effort `try?` decode behavior),
/// whereas a transport-level failure (e.g. AEAD/decrypt failure) throws.
protocol Transport: AnyObject {
    func encode(_ msg: ClientMessage) throws -> URLSessionWebSocketTask.Message
    func decode(_ message: URLSessionWebSocketTask.Message) throws -> ServerMessage?
}

/// Plaintext JSON over a WebSocket text frame. This is the DEFAULT transport and
/// preserves the exact behavior of the pre-refactor `ConnectionManager`.
final class PlaintextTransport: Transport {
    func encode(_ msg: ClientMessage) throws -> URLSessionWebSocketTask.Message {
        let data = try MaverickJSON.encoder().encode(msg)
        // JSON output is always valid UTF-8; guard defensively anyway.
        guard let text = String(data: data, encoding: .utf8) else {
            throw TransportError.encodingFailed
        }
        return .string(text)
    }

    func decode(_ message: URLSessionWebSocketTask.Message) throws -> ServerMessage? {
        let data: Data
        switch message {
        case .string(let text):
            guard let d = text.data(using: .utf8) else { return nil }
            data = d
        case .data(let d):
            // Defensive: server should send text, but accept binary JSON too.
            data = d
        @unknown default:
            return nil
        }
        return try? MaverickJSON.decoder().decode(ServerMessage.self, from: data)
    }
}

/// Noise-encrypted transport for paired sessions.
///
/// `MaverickNoise.NoiseTransport` is a `struct` whose `encryptFrame`/`decryptFrame`
/// are `mutating` (each advances a per-direction ChaCha20-Poly1305 counter that
/// MUST progress monotonically and never reset). To let `encode`/`decode` mutate
/// those counters across calls — while `Transport` is a reference-typed protocol —
/// we hold the struct as a `var` inside this `final class`. The class instance is
/// shared by reference, so every encode/decode mutates the same counters in place.
///
/// Thread-safety: `ConnectionManager` drives all sends from its caller and all
/// receives serially from the read loop's completion handler. Those can race, so
/// each direction is guarded by a lock. Encrypts and decrypts use independent
/// CipherStates, so they take separate locks and never contend with each other.
final class NoiseTransportAdapter: Transport {
    private var transport: NoiseTransport
    private let sendLock = NSLock()
    private let recvLock = NSLock()

    init(_ transport: NoiseTransport) {
        self.transport = transport
    }

    func encode(_ msg: ClientMessage) throws -> URLSessionWebSocketTask.Message {
        let data = try MaverickJSON.encoder().encode(msg)
        sendLock.lock()
        defer { sendLock.unlock() }
        let frame = try transport.encryptFrame(data)
        return .string(frame)
    }

    func decode(_ message: URLSessionWebSocketTask.Message) throws -> ServerMessage? {
        let b64: String
        switch message {
        case .string(let text):
            b64 = text
        case .data(let d):
            // Defensive: daemon uses text frames, but a binary frame would carry
            // the same base64url payload bytes.
            guard let text = String(data: d, encoding: .utf8) else {
                throw TransportError.decodingFailed
            }
            b64 = text
        @unknown default:
            throw TransportError.decodingFailed
        }
        let plaintext: Data
        recvLock.lock()
        do {
            plaintext = try transport.decryptFrame(b64)
            recvLock.unlock()
        } catch {
            recvLock.unlock()
            throw error
        }
        return try? MaverickJSON.decoder().decode(ServerMessage.self, from: plaintext)
    }
}

enum TransportError: Error, Equatable {
    case encodingFailed
    case decodingFailed
}
