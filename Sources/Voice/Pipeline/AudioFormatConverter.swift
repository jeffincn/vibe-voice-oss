import AVFoundation
import Foundation

/// Converts tap buffers to 16 kHz mono Float32 using incremental linear resampling.
struct AudioFormatConverter: Sendable {
    private var resampler: StreamingResampler
    private(set) var inputSampleRate: Double

    init(inputSampleRate: Double = 48_000) {
        self.inputSampleRate = max(1, inputSampleRate)
        resampler = StreamingResampler(inputRate: self.inputSampleRate)
    }

    mutating func reset(inputSampleRate: Double) {
        self.inputSampleRate = max(1, inputSampleRate)
        resampler = StreamingResampler(inputRate: self.inputSampleRate)
    }

    /// Takes an already-downmixed buffer because the de-interleave has to happen on the
    /// tap thread, before the buffer is reclaimed.
    mutating func convert(mono: [Float], tapRate: Double) -> (samples: [Float], rms: Float) {
        guard !mono.isEmpty else { return ([], 0) }

        if tapRate >= 8_000, abs(tapRate - inputSampleRate) > 0.5 {
            reset(inputSampleRate: tapRate)
        }

        let meanSquare = mono.reduce(Float.zero) { $0 + $1 * $1 } / Float(mono.count)
        let rms = sqrt(meanSquare)
        let resampled = resampler.push(mono)
        return (resampled, rms)
    }
}
