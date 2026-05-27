import XCTest
@testable import MaverickAgent

final class CircularBufferTests: XCTestCase {
    func testAppendAndRetrieve() {
        var buf = CircularBuffer<Int>(capacity: 4)
        buf.append(1); buf.append(2); buf.append(3)
        XCTAssertEqual(buf.snapshot(), [1, 2, 3])
    }

    func testOverflowEvictsOldest() {
        var buf = CircularBuffer<Int>(capacity: 3)
        buf.append(1); buf.append(2); buf.append(3); buf.append(4)
        XCTAssertEqual(buf.snapshot(), [2, 3, 4])
    }

    func testAppendContentsOf() {
        var buf = CircularBuffer<Int>(capacity: 3)
        buf.append(contentsOf: [1, 2, 3, 4, 5])
        XCTAssertEqual(buf.snapshot(), [3, 4, 5])
    }

    func testEmptyBuffer() {
        let buf = CircularBuffer<Int>(capacity: 4)
        XCTAssertTrue(buf.isEmpty)
        XCTAssertEqual(buf.snapshot(), [])
    }
}
