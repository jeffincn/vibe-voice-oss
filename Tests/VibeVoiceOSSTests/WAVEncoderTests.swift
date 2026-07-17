import XCTest
@testable import VibeVoiceOSS

final class WAVEncoderTests: XCTestCase {
    func testWAVHeaderAndOutputRate() {
        let input = [Float](repeating: 0.25, count: 48_000)
        let data = WAVEncoder.encode(samples: input, inputSampleRate: 48_000)

        XCTAssertEqual(String(data: data[0..<4], encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
        XCTAssertEqual(data.count, 44 + 16_000 * 2)

        let rate = data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: rate), 16_000)
    }

    func testResamplingPreservesDuration() {
        let output = WAVEncoder.resample(
            samples: [Float](repeating: 0, count: 44_100),
            from: 44_100,
            to: 16_000
        )
        XCTAssertEqual(output.count, 16_000)
    }
}
