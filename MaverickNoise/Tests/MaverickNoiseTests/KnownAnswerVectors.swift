import XCTest
import CryptoKit
@testable import MaverickNoise

/// Task A7 — Cross-language Known-Answer Tests (the correctness anchor).
///
/// These vectors were computed with an INDEPENDENT reference implementation
/// (python3 `hashlib`/`hmac`), NOT by the Swift code under test, and pasted here.
/// They lock the deterministic Noise primitives to known bytes so a wrong
/// HKDF order / hash seed is caught at the cheapest possible point. The full
/// end-to-end byte-compatibility proof against the daemon's `snow` responder
/// is the live interop test in Phase E.
///
/// Reference (reproducible):
///   import hashlib, hmac
///   name = b"Noise_XX_25519_ChaChaPoly_SHA256"   # exactly 32 bytes
///   # init hash: h0 = name (32B); mixHash(empty prologue) = SHA256(h0)
///   #   -> f3d15e6108ed9556171207baa58f97d29a13c6be40595166066e2e0958dc002d
///   ck  = bytes([0x01]*32); ikm = bytes([0x02]*32)
///   prk  = hmac.new(ck, ikm, hashlib.sha256).digest()
///   out1 = hmac.new(prk, b"\x01", hashlib.sha256).digest()
///   out2 = hmac.new(prk, out1 + b"\x02", hashlib.sha256).digest()
final class KnownAnswerVectors: XCTestCase {
    static let hkdfOut1 = "0d1e94c641dfd61a216ed04f1b390079459dea71ae4d466f574c260d1b6554db"
    static let hkdfOut2 = "b4069ed7a4a753cb5c779fb38a33dc02c63199ce58b6b7bf56286b844cacc358"
    static let symInitHash = "f3d15e6108ed9556171207baa58f97d29a13c6be40595166066e2e0958dc002d"

    private func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }

    func testHKDFNoiseKAT() {
        let outs = HKDFNoise.derive(chainingKey: Data(repeating: 0x01, count: 32),
                                    ikm: Data(repeating: 0x02, count: 32),
                                    count: 2)
        XCTAssertEqual(hex(outs[0]), Self.hkdfOut1)
        XCTAssertEqual(hex(outs[1]), Self.hkdfOut2)
    }

    func testSymmetricStateInitHashKAT() {
        XCTAssertEqual(hex(SymmetricState().handshakeHash), Self.symInitHash)
    }
}
