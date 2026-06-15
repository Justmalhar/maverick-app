import XCTest
@testable import MaverickNoise

final class NoiseTransportTests: XCTestCase {
    func testInitiatorSendDecryptableByResponderOrder() throws {
        let k1 = Data(repeating: 1, count: 32), k2 = Data(repeating: 2, count: 32)
        var initiator = NoiseTransport(send: k1, recv: k2)
        var responder = NoiseTransport(send: k2, recv: k1) // mirror
        let frame = try initiator.encryptFrame(Data("hi".utf8)) // base64url string
        XCTAssertEqual(try responder.decryptFrame(frame), Data("hi".utf8))
    }
    func testNonceProgressesAcrossFrames() throws {
        let k1 = Data(repeating: 3, count: 32), k2 = Data(repeating: 4, count: 32)
        var initiator = NoiseTransport(send: k1, recv: k2)
        var responder = NoiseTransport(send: k2, recv: k1)
        let f1 = try initiator.encryptFrame(Data("one".utf8))
        let f2 = try initiator.encryptFrame(Data("two".utf8))
        XCTAssertEqual(try responder.decryptFrame(f1), Data("one".utf8))
        XCTAssertEqual(try responder.decryptFrame(f2), Data("two".utf8))
    }
}
