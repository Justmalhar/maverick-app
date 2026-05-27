import XCTest
@testable import MaverickAgent

final class SessionManagerTests: XCTestCase {
    func testCreateAndListSession() async throws {
        let mgr = SessionManager()
        let info = try await mgr.createSession(name: "test", shell: "/bin/sh")
        let list = await mgr.listSessions()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].id, info.id)
        XCTAssertEqual(list[0].name, "test")
        await mgr.closeSession(id: info.id)
    }

    func testCloseSessionRemovesIt() async throws {
        let mgr = SessionManager()
        let info = try await mgr.createSession(name: "bye", shell: "/bin/sh")
        await mgr.closeSession(id: info.id)
        let list = await mgr.listSessions()
        XCTAssertTrue(list.isEmpty)
    }

    func testScrollbackEmptyOnNewSession() async throws {
        let mgr = SessionManager()
        let info = try await mgr.createSession(name: "s", shell: "/bin/sh")
        // Give shell a moment to emit prompt, then read scrollback
        try await Task.sleep(for: .milliseconds(200))
        let sb = await mgr.getScrollback(sessionId: info.id)
        XCTAssertNotNil(sb)
        await mgr.closeSession(id: info.id)
    }
}
