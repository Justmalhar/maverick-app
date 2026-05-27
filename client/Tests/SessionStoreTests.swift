// client/Tests/SessionStoreTests.swift
import XCTest
@testable import MaverickRemote
import MaverickProtocol

final class SessionStoreTests: XCTestCase {
    func testSessionListMessagePopulatesStore() {
        let store = SessionStore()
        let sessions = [
            SessionInfo(name: "claude", shell: "/bin/zsh"),
            SessionInfo(name: "bash", shell: "/bin/bash")
        ]
        store.handle(.sessionList(sessions: sessions))
        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(store.sessions[0].name, "claude")
    }

    func testSessionCreatedAppendsIfNotPresent() {
        let store = SessionStore()
        let info = SessionInfo(name: "new", shell: "/bin/zsh")
        store.handle(.sessionCreated(session: info))
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions[0].id, info.id)
    }

    func testSessionClosedRemovesEntry() {
        let store = SessionStore()
        let info = SessionInfo(name: "bye", shell: "/bin/zsh")
        store.handle(.sessionCreated(session: info))
        store.handle(.sessionClosed(sessionId: info.id))
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testActiveSessionClearedWhenClosed() {
        let store = SessionStore()
        let info = SessionInfo(name: "active", shell: "/bin/zsh")
        store.handle(.sessionCreated(session: info))
        store.activeSessionId = info.id
        store.handle(.sessionClosed(sessionId: info.id))
        XCTAssertNil(store.activeSessionId)
    }
}
