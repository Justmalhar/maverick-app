// client/Tests/ConnectionManagerTests.swift
import XCTest
@testable import MaverickRemote
import MaverickProtocol

final class ConnectionManagerTests: XCTestCase {
    func testInitialStateIsDisconnected() {
        let mgr = ConnectionManager()
        XCTAssertEqual(mgr.state, .disconnected)
    }

    func testReconnectDelayDoublesUpToMax() {
        let mgr = ConnectionManager()
        XCTAssertEqual(mgr.nextDelay(), 1.0)
        mgr.recordFailure()
        XCTAssertEqual(mgr.nextDelay(), 2.0)
        mgr.recordFailure()
        XCTAssertEqual(mgr.nextDelay(), 4.0)
        // Saturate
        for _ in 0..<10 { mgr.recordFailure() }
        XCTAssertEqual(mgr.nextDelay(), 30.0)
    }

    func testResetDelayClearsBackoff() {
        let mgr = ConnectionManager()
        mgr.recordFailure(); mgr.recordFailure()
        mgr.resetDelay()
        XCTAssertEqual(mgr.nextDelay(), 1.0)
    }
}
