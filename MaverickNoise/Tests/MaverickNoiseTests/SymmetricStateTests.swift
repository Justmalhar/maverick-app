import XCTest
import CryptoKit
@testable import MaverickNoise

final class SymmetricStateTests: XCTestCase {
    func testProtocolNameSeedsHashTo32Bytes() {
        let s = SymmetricState()
        XCTAssertEqual(s.handshakeHash.count, 32)
        // name is exactly 32 bytes -> h == the raw ASCII name before mixHash(prologue)
    }
    func testUnkeyedEncryptIsPlaintextPassthrough() throws {
        var s = SymmetricState()
        let pt = Data("token-bytes".utf8)
        let out = try s.encryptAndHash(pt)
        XCTAssertEqual(out, pt) // no key yet -> no AEAD, no tag
    }
    func testMixHashChangesHash() {
        var s = SymmetricState()
        let h0 = s.handshakeHash
        s.mixHash(Data([1,2,3]))
        XCTAssertNotEqual(s.handshakeHash, h0)
    }
    // Cross-language KAT (Task A7): seeded SymmetricState hash after init.
    // h0 = the 32-byte ASCII protocol name; mixHash(empty prologue) = SHA256(h0).
    // Independent reference (python3 hashlib):
    //   SHA256("Noise_XX_25519_ChaChaPoly_SHA256") == init hash (name is exactly 32 bytes).
    func testInitHashMatchesRust() {
        let s = SymmetricState()
        XCTAssertEqual(s.handshakeHash.map { String(format: "%02x", $0) }.joined(),
                       "f3d15e6108ed9556171207baa58f97d29a13c6be40595166066e2e0958dc002d")
        // sanity: equals SHA256 of the protocol name
        let nameHash = Data(SHA256.hash(data: Data(SymmetricState.protocolName.utf8)))
        XCTAssertEqual(s.handshakeHash, nameHash)
    }
}
