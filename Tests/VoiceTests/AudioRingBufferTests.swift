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

    func testEmptyRingReadsAsEmpty() {
        let ring = AudioRingBuffer(capacity: 4)
        XCTAssertEqual(ring.sampleCount, 0)
        XCTAssertEqual(ring.snapshot(), [])
        XCTAssertEqual(ring.last(3), [])
    }

    func testSampleCountSaturatesAtCapacity() {
        var ring = AudioRingBuffer(capacity: 4)
        ring.append([1, 2])
        XCTAssertEqual(ring.sampleCount, 2)
        ring.append([3, 4, 5, 6, 7])
        XCTAssertEqual(ring.sampleCount, 4)
        XCTAssertEqual(ring.snapshot(), [4, 5, 6, 7])
    }

    /// A block longer than the ring must leave the newest tail behind, not the head.
    func testWritingMoreThanCapacityAtOnceKeepsTheNewestSamples() {
        var ring = AudioRingBuffer(capacity: 3)
        ring.append([1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(ring.snapshot(), [5, 6, 7])
    }

    func testResetClearsWithoutDisturbingLaterWrites() {
        var ring = AudioRingBuffer(capacity: 4)
        ring.append([1, 2, 3])
        ring.reset()
        XCTAssertEqual(ring.sampleCount, 0)
        XCTAssertEqual(ring.snapshot(), [])

        ring.append([9, 8])
        XCTAssertEqual(ring.snapshot(), [9, 8])
    }

    func testLastClampsToWhatIsAvailable() {
        var ring = AudioRingBuffer(capacity: 8)
        ring.append([1, 2, 3])
        XCTAssertEqual(ring.last(10), [1, 2, 3])
        XCTAssertEqual(ring.last(0), [])
        XCTAssertEqual(ring.last(-5), [])
    }

    func testCapacityIsNeverZero() {
        var ring = AudioRingBuffer(capacity: 0)
        XCTAssertEqual(ring.capacity, 1)
        ring.append([1, 2, 3])
        XCTAssertEqual(ring.snapshot(), [3])
    }

    func testAppendingNothingIsANoop() {
        var ring = AudioRingBuffer(capacity: 4)
        ring.append([1, 2])
        ring.append([])
        XCTAssertEqual(ring.snapshot(), [1, 2])
    }
}
