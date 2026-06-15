import XCTest
@testable import MaverickNoise

final class Base64URLTests: XCTestCase {
    func testEncodeIsUrlSafeNoPad() {
        // 0xFB 0xFF -> standard "+/" alphabet would yield "+/8"; url-safe yields "-_8"
        let d = Data([0xfb, 0xff])
        XCTAssertEqual(Base64URL.encode(d), "-_8")
    }
    func testDecodeAcceptsPaddedAndUnpadded() throws {
        XCTAssertEqual(try Base64URL.decode("-_8"), Data([0xfb, 0xff]))
        XCTAssertEqual(try Base64URL.decode("-_8="), Data([0xfb, 0xff]))
    }
    func testRoundTrip32Bytes() throws {
        let d = Data((0..<32).map { UInt8($0) })
        XCTAssertEqual(try Base64URL.decode(Base64URL.encode(d)), d)
        XCTAssertEqual(Base64URL.encode(d).count, 43) // 32 bytes -> 43 url-safe chars, no pad
    }
}
