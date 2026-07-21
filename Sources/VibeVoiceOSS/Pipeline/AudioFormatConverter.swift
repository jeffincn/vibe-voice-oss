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

    mutating func convert(buffer: AVAudioPCMBuffer) -> (samples: [Float], rms: Float) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return ([], 0)
        }

        let bufferRate = buffer.format.sampleRate
        if bufferRate >= 8_000, abs(bufferRate - inputSampleRate) > 0.5 {
            reset(inputSampleRate: bufferRate)
        }

        var mono = [Float](repeating: 0, count: frameCount)
        if let channels = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let source = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += source[frame] / Float(channelCount)
                }
            }
        } else if let channels = buffer.int16ChannelData {
            let scale: Float = 1.0 / Float(Int16.max)
            for channel in 0..<channelCount {
                let source = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += Float(source[frame]) * scale / Float(channelCount)
                }
            }
        } else {
            return ([], 0)
        }

        let meanSquare = mono.reduce(Float.zero) { $0 + $1 * $1 } / Float(frameCount)
        let rms = sqrt(meanSquare)
        let resampled = resampler.push(mono)
        return (resampled, rms)
    }
}
