import XCTest
import CryptoKit
@testable import MaverickNoise

final class FingerprintTests: XCTestCase {
    func testShortFingerprintIs8UpperHexOfSha256Prefix() {
        let key = Data(repeating: 0xAB, count: 32)
        let fp = Fingerprint.short(key)
        XCTAssertEqual(fp.count, 8)
        XCTAssertEqual(fp, fp.uppercased())
        // matches first 4 bytes of SHA256(key) as upper hex
        let expect = Data(SHA256.hash(data: key)).prefix(4).map { String(format: "%02X", $0) }.joined()
        XCTAssertEqual(fp, expect)
    }
    func testSafetyNumberIsFiveSixDigitGroups() {
        let key = Data(repeating: 0x01, count: 32)
        let sn = Fingerprint.safetyNumber(key)
        let groups = sn.split(separator: " ")
        XCTAssertEqual(groups.count, 5)
        XCTAssertTrue(groups.allSatisfy { $0.count == 6 })
    }
    func testDeviceIdIsBase64UrlOfSha256() {
        let key = Data(repeating: 0x05, count: 32)
        let id = Fingerprint.deviceId(key)
        XCTAssertEqual(try Base64URL.decode(id), Data(SHA256.hash(data: key)))
    }
}
