import XCTest
@testable import MaverickRemote
import MaverickNoise

final class QRPayloadTests: XCTestCase {
    // 32-byte key 0x00…0x1F and its base64url; 16-byte token 0x00…0x0F.
    private let k32 = Data((0..<32).map { UInt8($0) })
    private let e32 = Data((0..<32).map { UInt8(0x80 &+ UInt8($0)) })
    private let t16 = Data((0..<16).map { UInt8($0) })

    private var kStr: String { Base64URL.encode(k32) }
    private var eStr: String { Base64URL.encode(e32) }
    private var tStr: String { Base64URL.encode(t16) }
    private var kFingerprint: String { Fingerprint.short(k32) }

    func testFullValidPayload() throws {
        let url = "maverick://pair/v1?k=\(kStr)&e=\(eStr)&t=\(tStr)&r=host%3A8765&n=My%20Mac&f=\(kFingerprint)"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.staticKey, k32)
        XCTAssertEqual(p.staticKey.count, 32)
        XCTAssertEqual(p.ephemeralHint, e32)
        XCTAssertEqual(p.ephemeralHint.count, 32)
        XCTAssertEqual(p.token, t16)
        XCTAssertEqual(p.token.count, 16)
        XCTAssertEqual(p.host, "host")
        XCTAssertEqual(p.port, 8765)
        XCTAssertEqual(p.name, "My Mac")
        XCTAssertEqual(p.fingerprint, kFingerprint)
    }

    func testMissingKIsRejected() {
        let url = "maverick://pair/v1?e=\(eStr)&t=\(tStr)"
        XCTAssertThrowsError(try QRPayload.parse(url)) { err in
            XCTAssertEqual(err as? QRPayloadError, .missingRequiredField("k"))
        }
    }

    func testMissingTIsRejected() {
        let url = "maverick://pair/v1?k=\(kStr)&e=\(eStr)"
        XCTAssertThrowsError(try QRPayload.parse(url)) { err in
            XCTAssertEqual(err as? QRPayloadError, .missingRequiredField("t"))
        }
    }

    func testWrongSchemeIsRejected() {
        let url = "mav://pair/v1?k=\(kStr)&t=\(tStr)"
        XCTAssertThrowsError(try QRPayload.parse(url)) { err in
            XCTAssertEqual(err as? QRPayloadError, .wrongScheme)
        }
    }

    func testWrongPathIsRejected() {
        let url = "maverick://pair/v2?k=\(kStr)&t=\(tStr)"
        XCTAssertThrowsError(try QRPayload.parse(url)) { err in
            XCTAssertEqual(err as? QRPayloadError, .wrongPath)
        }
    }

    func testWrongLengthKIsRejected() {
        let short = Base64URL.encode(Data((0..<16).map { UInt8($0) })) // 16 bytes, not 32
        let url = "maverick://pair/v1?k=\(short)&t=\(tStr)"
        XCTAssertThrowsError(try QRPayload.parse(url)) { err in
            XCTAssertEqual(err as? QRPayloadError,
                           .wrongKeyLength(field: "k", expected: 32, actual: 16))
        }
    }

    func testRendezvousWithSchemeAndPathStripped() throws {
        // ws://10.0.0.5:9000/pair → host 10.0.0.5, port 9000.
        let r = "ws://10.0.0.5:9000/pair"
        let encoded = r.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&r=\(encoded)"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.host, "10.0.0.5")
        XCTAssertEqual(p.port, 9000)
    }

    func testRendezvousBareHostPort() throws {
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&r=example.local%3A5555"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.host, "example.local")
        XCTAssertEqual(p.port, 5555)
    }

    func testRendezvousBareHostDefaultsPort() throws {
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&r=just-a-host"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.host, "just-a-host")
        XCTAssertEqual(p.port, 8765)
    }

    func testRendezvousAbsentFallsBack() throws {
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.host, "pair.local")
        XCTAssertEqual(p.port, 8765)
    }

    func testRendezvousIPv6BracketGuard() throws {
        // [::1]:8765 → host "[::1]", port 8765 (colon inside brackets ignored).
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&r=%5B%3A%3A1%5D%3A8765"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.host, "[::1]")
        XCTAssertEqual(p.port, 8765)
    }

    func testRendezvousBareIPv6NoPort() throws {
        // [::1] with no port → host "[::1]", default port.
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&r=%5B%3A%3A1%5D"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.host, "[::1]")
        XCTAssertEqual(p.port, 8765)
    }

    func testFingerprintMismatchIsRejected() {
        // Supply a fingerprint that does not match k.
        let bogus = "DEADBEEF"
        XCTAssertNotEqual(bogus, kFingerprint)
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&f=\(bogus)"
        XCTAssertThrowsError(try QRPayload.parse(url)) { err in
            guard case .fingerprintMismatch = (err as? QRPayloadError) else {
                return XCTFail("expected fingerprintMismatch, got \(err)")
            }
        }
    }

    func testFingerprintMatchCaseInsensitive() throws {
        let url = "maverick://pair/v1?k=\(kStr)&t=\(tStr)&f=\(kFingerprint.lowercased())"
        let p = try QRPayload.parse(url)
        XCTAssertEqual(p.fingerprint, kFingerprint.lowercased())
    }
}
