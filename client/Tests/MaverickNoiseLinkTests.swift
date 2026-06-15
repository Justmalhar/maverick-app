import XCTest
import MaverickNoise

final class MaverickNoiseLinkTests: XCTestCase {
    func testBase64URLEncodeResolvesFromTestTarget() {
        XCTAssertEqual(Base64URL.encode(Data([0xfb, 0xff])), "-_8")
    }
}
