import XCTest
import CryptoKit
@testable import MaverickNoise

final class CipherStateTests: XCTestCase {
    func testEncryptDecryptRoundTripWithAAD() throws {
        let key = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        var enc = CipherState(key: key)
        var dec = CipherState(key: key)
        let aad = Data("hash".utf8)
        let pt = Data("{\"type\":\"list_sessions\"}".utf8)
        let ct = try enc.encrypt(plaintext: pt, aad: aad)
        XCTAssertEqual(ct.count, pt.count + 16) // + Poly1305 tag
        XCTAssertEqual(try dec.decrypt(ciphertext: ct, aad: aad), pt)
    }
    func testNonceIncrementsPerMessage() throws {
        let key = Data(repeating: 9, count: 32)
        var enc = CipherState(key: key)
        let a = try enc.encrypt(plaintext: Data([1]), aad: Data())
        let b = try enc.encrypt(plaintext: Data([1]), aad: Data())
        XCTAssertNotEqual(a, b) // same pt, different nonce -> different ct
    }
    func testNonceLayoutIsFourZeroThenLE64() {
        XCTAssertEqual(CipherState.nonce(counter: 5),
                       Data([0,0,0,0, 5,0,0,0,0,0,0,0]))
        XCTAssertEqual(CipherState.nonce(counter: 258),
                       Data([0,0,0,0, 2,1,0,0,0,0,0,0]))
    }
}
