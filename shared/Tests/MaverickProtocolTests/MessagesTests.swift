// shared/Tests/MaverickProtocolTests/MessagesTests.swift
import XCTest
@testable import MaverickProtocol

final class MessagesTests: XCTestCase {
    let encoder = MaverickJSON.encoder()
    let decoder = MaverickJSON.decoder()

    func testSessionInfoRoundtrip() throws {
        // Truncate to whole seconds — ISO8601 default strategy has second precision.
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let info = SessionInfo(id: UUID(), name: "test", shell: "/bin/zsh", createdAt: now)
        let data = try encoder.encode(info)
        let decoded = try decoder.decode(SessionInfo.self, from: data)
        XCTAssertEqual(decoded.id, info.id)
        XCTAssertEqual(decoded.name, info.name)
        XCTAssertEqual(decoded.shell, info.shell)
        XCTAssertEqual(decoded.createdAt, info.createdAt)
    }

    func testClientMessageCreateSessionRoundtrip() throws {
        let msg = ClientMessage.createSession(name: "claude", shell: "/bin/zsh", cwd: "~/projects")
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ClientMessage.self, from: data)
        guard case .createSession(let name, let shell, let cwd) = decoded else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(name, "claude")
        XCTAssertEqual(shell, "/bin/zsh")
        XCTAssertEqual(cwd, "~/projects")
    }

    func testServerMessageOutputRoundtrip() throws {
        let id = UUID()
        let msg = ServerMessage.output(sessionId: id, data: "aGVsbG8=")
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ServerMessage.self, from: data)
        guard case .output(let sid, let b64) = decoded else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(sid, id)
        XCTAssertEqual(b64, "aGVsbG8=")
    }

    func testMalformedJSONThrows() {
        let bad = Data("{\"type\":\"unknown_type\"}".utf8)
        XCTAssertThrowsError(try decoder.decode(ClientMessage.self, from: bad))
    }

    func testClientMessageRejectsServerDiscriminator() {
        // After splitting MessageType, a server-only discriminator should be rejected by ClientMessage.
        let id = UUID()
        let payload = "{\"type\":\"output\",\"sessionId\":\"\(id.uuidString)\",\"data\":\"aGk=\"}"
        XCTAssertThrowsError(try decoder.decode(ClientMessage.self, from: Data(payload.utf8)))
    }
}
