// server/Tests/WebSocketIntegrationTests.swift
import XCTest
import Foundation
@testable import MaverickAgent
import MaverickProtocol

final class WebSocketIntegrationTests: XCTestCase {
    func testConnectListAndCreateSession() async throws {
        let mgr = SessionManager()
        let server = WebSocketServer(sessionManager: mgr, port: 0) // port 0 = ephemeral
        try server.start()
        let port = try XCTUnwrap(server.actualPort)

        let url = URL(string: "ws://127.0.0.1:\(port)/ws")!
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        // Send list_sessions
        let listMsg = try MaverickJSON.encoder().encode(ClientMessage.listSessions)
        try await task.send(.string(String(data: listMsg, encoding: .utf8)!))

        // Receive session_list
        let response = try await task.receive()
        guard case .string(let text) = response,
              let data = text.data(using: .utf8),
              case .sessionList(let sessions) = try MaverickJSON.decoder().decode(ServerMessage.self, from: data)
        else { return XCTFail("expected session_list") }
        XCTAssertTrue(sessions.isEmpty)

        task.cancel()
        server.stop()
    }
}
