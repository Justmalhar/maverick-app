import XCTest
@testable import MaverickProtocol

final class MessagesTests: XCTestCase {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    func testSessionInfoRoundtrip() throws {
        let info = SessionInfo(id: UUID(), name: "test", shell: "/bin/zsh", createdAt: Date())
        let data = try encoder.encode(info)
        let decoded = try decoder.decode(SessionInfo.self, from: data)
        XCTAssertEqual(decoded.id, info.id)
        XCTAssertEqual(decoded.name, info.name)
        XCTAssertEqual(decoded.shell, info.shell)
    }

    func testClientMessageCreateSessionRoundtrip() throws {
        let msg = ClientMessage.createSession(name: "claude", shell: "/bin/zsh")
        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ClientMessage.self, from: data)
        guard case .createSession(let name, let shell) = decoded else {
            return XCTFail("wrong case")
        }
        XCTAssertEqual(name, "claude")
        XCTAssertEqual(shell, "/bin/zsh")
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
}
