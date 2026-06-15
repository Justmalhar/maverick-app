// client/Tests/TransportTests.swift
import XCTest
@testable import MaverickRemote
import MaverickProtocol
import MaverickNoise

final class TransportTests: XCTestCase {

    // MARK: - PlaintextTransport

    func testPlaintextEncodeProducesStringJSON() throws {
        let transport = PlaintextTransport()
        let wire = try transport.encode(.listSessions)
        guard case .string(let text) = wire else {
            return XCTFail("plaintext encode must produce a .string frame")
        }
        // The encoded JSON carries the protocol type tag.
        XCTAssertTrue(text.contains("list_sessions"), "got: \(text)")
        // And it must be valid UTF-8 JSON.
        XCTAssertNotNil(text.data(using: .utf8))
    }

    func testPlaintextDecodesKnownServerMessageJSON() throws {
        let transport = PlaintextTransport()
        // A known, minimal ServerMessage JSON: an empty session list.
        let json = #"{"type":"session_list","sessions":[]}"#
        let decoded = try transport.decode(.string(json))
        guard case .sessionList(let sessions) = decoded else {
            return XCTFail("expected sessionList, got \(String(describing: decoded))")
        }
        XCTAssertTrue(sessions.isEmpty)
    }

    func testPlaintextDecodeOfUnknownFrameIsNil() throws {
        let transport = PlaintextTransport()
        XCTAssertNil(try transport.decode(.string("not json at all")))
    }

    // MARK: - NoiseTransportAdapter (mirrored keys, no socket)

    /// Build a client adapter (send=k1, recv=k2) and a mirrored server-side
    /// `NoiseTransport` (send=k2, recv=k1). A ClientMessage encoded by the
    /// adapter must decrypt + decode on the server side; this proves the adapter
    /// wraps the mutating struct correctly without a real socket.
    func testNoiseAdapterClientToServer() throws {
        let k1 = Data((0..<32).map { UInt8($0) })
        let k2 = Data((0..<32).map { UInt8(0xFF - $0) })

        let clientAdapter = NoiseTransportAdapter(NoiseTransport(send: k1, recv: k2))
        var server = NoiseTransport(send: k2, recv: k1) // mirror

        let wire = try clientAdapter.encode(.listSessions)
        guard case .string(let b64) = wire else {
            return XCTFail("noise encode must produce a .string frame")
        }

        let plaintext = try server.decryptFrame(b64)
        let decoded = try MaverickJSON.decoder().decode(ClientMessage.self, from: plaintext)
        guard case .listSessions = decoded else {
            return XCTFail("server failed to recover ClientMessage.listSessions")
        }
    }

    /// Round-trip a ServerMessage the other direction: the server-side transport
    /// encrypts a ServerMessage frame, and the client adapter's `decode` recovers it.
    func testNoiseAdapterServerToClient() throws {
        let k1 = Data((0..<32).map { UInt8($0) })
        let k2 = Data((0..<32).map { UInt8(0xFF - $0) })

        let clientAdapter = NoiseTransportAdapter(NoiseTransport(send: k1, recv: k2))
        var server = NoiseTransport(send: k2, recv: k1) // mirror

        let json = #"{"type":"session_list","sessions":[]}"#
        let frame = try server.encryptFrame(Data(json.utf8))

        let decoded = try clientAdapter.decode(.string(frame))
        guard case .sessionList(let sessions) = decoded else {
            return XCTFail("client adapter failed to recover ServerMessage.sessionList")
        }
        XCTAssertTrue(sessions.isEmpty)
    }

    /// Counters must advance monotonically across calls: two encodes of the same
    /// message produce different ciphertext, and the server decrypts both in order.
    func testNoiseAdapterCounterProgression() throws {
        let k1 = Data(repeating: 0x11, count: 32)
        let k2 = Data(repeating: 0x22, count: 32)

        let clientAdapter = NoiseTransportAdapter(NoiseTransport(send: k1, recv: k2))
        var server = NoiseTransport(send: k2, recv: k1)

        guard case .string(let a) = try clientAdapter.encode(.listSessions),
              case .string(let b) = try clientAdapter.encode(.listSessions) else {
            return XCTFail("expected .string frames")
        }
        XCTAssertNotEqual(a, b, "same message + advancing counter must differ on the wire")

        // The server decrypts them in the same order the client produced them.
        _ = try server.decryptFrame(a)
        _ = try server.decryptFrame(b)
    }

    /// Decode-direction counterpart of `testNoiseAdapterCounterProgression`:
    /// a mirrored-key "server" `NoiseTransport` encrypts TWO ServerMessage
    /// frames (recv counters 0 then 1); the client adapter's `decode` must
    /// recover BOTH in order. Replaying frame-0 after frame-1 must fail to
    /// decode (counter desync / out-of-order detection).
    func testNoiseAdapterServerToClientCounterProgression() throws {
        let k1 = Data(repeating: 0x33, count: 32)
        let k2 = Data(repeating: 0x44, count: 32)

        let clientAdapter = NoiseTransportAdapter(NoiseTransport(send: k1, recv: k2))
        var server = NoiseTransport(send: k2, recv: k1) // mirror

        // Two distinct server frames so we can tell which one decoded.
        let json0 = #"{"type":"session_list","sessions":[]}"#
        let json1 = #"{"type":"session_list","sessions":[]}"#
        let frame0 = try server.encryptFrame(Data(json0.utf8)) // counter 0
        let frame1 = try server.encryptFrame(Data(json1.utf8)) // counter 1
        XCTAssertNotEqual(frame0, frame1, "advancing send counter must differ on the wire")

        // Decode both, in order, through the client adapter.
        let decoded0 = try clientAdapter.decode(.string(frame0))
        guard case .sessionList(let s0) = decoded0 else {
            return XCTFail("client adapter failed to recover frame-0 sessionList")
        }
        XCTAssertTrue(s0.isEmpty)

        let decoded1 = try clientAdapter.decode(.string(frame1))
        guard case .sessionList(let s1) = decoded1 else {
            return XCTFail("client adapter failed to recover frame-1 sessionList")
        }
        XCTAssertTrue(s1.isEmpty)

        // Replaying frame-0 now (recv counter has advanced past 0) must throw:
        // the AEAD nonce no longer matches, so decryptFrame fails.
        XCTAssertThrowsError(try clientAdapter.decode(.string(frame0)),
                             "replaying an out-of-order frame must fail to decrypt")
    }
}
