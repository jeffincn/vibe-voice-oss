import XCTest
@testable import VibeVoiceOSS

final class AudioRingBufferTests: XCTestCase {
    func testAppendAndSnapshotPreservesOrder() {
        var ring = AudioRingBuffer(capacity: 8)
        ring.append([1, 2, 3, 4])
        ring.append([5, 6])
        XCTAssertEqual(ring.snapshot(), [1, 2, 3, 4, 5, 6])
        ring.append([7, 8, 9, 10])
        XCTAssertEqual(ring.snapshot(), [3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(ring.last(3), [8, 9, 10])
    }
}
