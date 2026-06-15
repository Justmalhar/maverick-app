import XCTest
@testable import MaverickRemote

final class KeychainStoreTests: XCTestCase {
    private var service: String!
    private var store: KeychainStore!

    override func setUpWithError() throws {
        // Unique service per test run so we never touch the real app keychain.
        service = "test.maverick.pairing.\(UUID().uuidString)"
        store = KeychainStore(service: service)
        try store.deleteAll()
    }

    override func tearDownWithError() throws {
        // Remove everything this test wrote.
        try store.deleteAll()
        store = nil
        service = nil
    }

    func testStaticIdentityStableAcrossLoads() throws {
        let first = try store.loadOrCreateStaticIdentity()
        let second = try store.loadOrCreateStaticIdentity()
        XCTAssertEqual(first.rawRepresentation, second.rawRepresentation)
        XCTAssertEqual(first.publicKey.rawRepresentation, second.publicKey.rawRepresentation)
        XCTAssertEqual(first.rawRepresentation.count, 32)
    }

    func testStaticIdentityFreshServiceDiffers() throws {
        let mine = try store.loadOrCreateStaticIdentity()
        let otherService = "test.maverick.pairing.\(UUID().uuidString)"
        let other = KeychainStore(service: otherService)
        defer { try? other.deleteAll() }
        let theirs = try other.loadOrCreateStaticIdentity()
        XCTAssertNotEqual(mine.rawRepresentation, theirs.rawRepresentation)
    }

    func testPinFirstUseThenAlreadyPinned() throws {
        let host = "10.0.0.5:8765"
        let key = Data((0..<32).map { UInt8($0) })

        XCTAssertEqual(try store.pin(host: host, key: key), .firstUse)
        XCTAssertEqual(try store.pin(host: host, key: key), .alreadyPinned)
        XCTAssertEqual(try store.pinnedKey(host: host), key)
    }

    func testPinMismatchForDifferentKeySameHost() throws {
        let host = "10.0.0.5:8765"
        let key = Data((0..<32).map { UInt8($0) })
        let other = Data((0..<32).map { UInt8(0xFF &- UInt8($0)) })

        XCTAssertEqual(try store.pin(host: host, key: key), .firstUse)
        XCTAssertEqual(try store.pin(host: host, key: other), .mismatch)
        // The original pin must be unchanged after a mismatch.
        XCTAssertEqual(try store.pinnedKey(host: host), key)
    }

    func testDifferentHostsPinIndependently() throws {
        let keyA = Data(repeating: 0xA1, count: 32)
        let keyB = Data(repeating: 0xB2, count: 32)
        XCTAssertEqual(try store.pin(host: "host-a", key: keyA), .firstUse)
        XCTAssertEqual(try store.pin(host: "host-b", key: keyB), .firstUse)
        XCTAssertEqual(try store.pin(host: "host-a", key: keyA), .alreadyPinned)
        XCTAssertEqual(try store.pin(host: "host-b", key: keyB), .alreadyPinned)
    }
}
