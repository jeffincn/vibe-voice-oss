import AVFoundation
import XCTest
@testable import MLXASR

final class Qwen3ASRAudioResampleTests: XCTestCase {
    func testLoadAudioResamplesOnceWithoutDuplicating() throws {
        // Generate a short 48kHz mono Float32 WAV, then ensure loadAudio() returns ~16kHz length.
        let tmp = FileManager.default.temporaryDirectory
        let url = tmp.appendingPathComponent("ontype-resample-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }

        let srcRate: Double = 48_000
        let dstRate: Double = 16_000
        let seconds: Double = 0.5
        let srcFrames = Int(srcRate * seconds)

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: srcRate, channels: 1, interleaved: false)!
        // Write file in a limited scope so the underlying writer is finalized before reading.
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)

            // Deterministic ramp signal (not silence) so duplication would be observable via length mismatch.
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(srcFrames))!
            buffer.frameLength = AVAudioFrameCount(srcFrames)
            let ptr = buffer.floatChannelData![0]
            for i in 0..<srcFrames {
                ptr[i] = Float(i) / Float(srcFrames) // 0..1 ramp
            }
            try file.write(from: buffer)
        }

        let out = try loadAudio(from: url)

        // Expected output frames after resampling.
        let expected = Int(dstRate * seconds)
        // Allow converter rounding/priming differences.
        XCTAssertGreaterThan(out.count, expected - 512)
        XCTAssertLessThan(out.count, expected + 512)

        // Ensure we did not accidentally duplicate input by returning a wildly larger buffer.
        XCTAssertLessThan(out.count, expected * 2)
    }
}
