import XCTest
import CryptoKit
@testable import MaverickNoise

final class HKDFNoiseTests: XCTestCase {
    func testTwoOutputsAre32BytesEach() {
        let ck = Data(repeating: 0x01, count: 32)
        let ikm = Data(repeating: 0x02, count: 32)
        let outs = HKDFNoise.derive(chainingKey: ck, ikm: ikm, count: 2)
        XCTAssertEqual(outs.count, 2)
        XCTAssertEqual(outs[0].count, 32)
        XCTAssertEqual(outs[1].count, 32)
        XCTAssertNotEqual(outs[0], outs[1])
    }
    func testEmptyIkmIsAccepted() { // the split() case
        let ck = Data(repeating: 0x07, count: 32)
        let outs = HKDFNoise.derive(chainingKey: ck, ikm: Data(), count: 2)
        XCTAssertEqual(outs.count, 2)
        XCTAssertEqual(outs[0].count, 32)
    }
    // Cross-language KAT (Task A7): computed with an independent reference
    // (python3 hmac/hashlib) for ck=[0x01;32], ikm=[0x02;32], count=2.
    func testKnownAnswer() {
        let ck = Data(repeating: 0x01, count: 32)
        let ikm = Data(repeating: 0x02, count: 32)
        let outs = HKDFNoise.derive(chainingKey: ck, ikm: ikm, count: 2)
        XCTAssertEqual(outs[0].map { String(format: "%02x", $0) }.joined(),
                       "0d1e94c641dfd61a216ed04f1b390079459dea71ae4d466f574c260d1b6554db")
        XCTAssertEqual(outs[1].map { String(format: "%02x", $0) }.joined(),
                       "b4069ed7a4a753cb5c779fb38a33dc02c63199ce58b6b7bf56286b844cacc358")
    }
}
