import XCTest
import CryptoKit
@testable import MaverickNoise

final class HandshakeShapeTests: XCTestCase {
    func testMsg1ShapeUnkeyedTokenPassthrough() throws {
        let clientStatic = Curve25519.KeyAgreement.PrivateKey()
        var hs = HandshakeStateInitiator(staticKey: clientStatic)
        let token = Data((0..<16).map { UInt8($0) })
        let msg1 = try hs.writeMsg1(token: token)
        // 32-byte ephemeral + plaintext token (no key yet, no tag)
        XCTAssertEqual(msg1.count, 32 + token.count)
    }

    func testWriteMsg3BeforeReadMsg2Throws() throws {
        let clientStatic = Curve25519.KeyAgreement.PrivateKey()
        var hs = HandshakeStateInitiator(staticKey: clientStatic)
        _ = try hs.writeMsg1(token: Data(repeating: 0, count: 16))
        XCTAssertThrowsError(try hs.writeMsg3()) { error in
            XCTAssertEqual(error as? NoiseError, .handshakeOutOfOrder)
        }
    }
}
