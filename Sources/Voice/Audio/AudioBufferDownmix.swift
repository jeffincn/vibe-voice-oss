import AVFoundation
import Foundation

enum AudioBufferDownmix {
    /// Mono Float32 for one tap buffer, or nil when the buffer carries no usable PCM.
    ///
    /// `floatChannelData` and `int16ChannelData` expose one pointer per channel only for
    /// a deinterleaved format. An interleaved buffer has a single allocation holding all
    /// channels, so `data[1]` on interleaved stereo reads past the end of the buffer
    /// list. AVAudioEngine hands out deinterleaved float most of the time, which is why
    /// this went unnoticed, but the tap also accepts the hardware format directly and
    /// some interfaces report interleaved there.
    static func mono(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return nil }

        var mono = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(channels)

        if let data = buffer.floatChannelData {
            if buffer.format.isInterleaved {
                let source = data[0]
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += source[frame * channels + channel]
                    }
                    mono[frame] = sum * scale
                }
            } else {
                for channel in 0..<channels {
                    let source = data[channel]
                    for frame in 0..<frames {
                        mono[frame] += source[frame] * scale
                    }
                }
            }
        } else if let data = buffer.int16ChannelData {
            let intScale = scale / Float(Int16.max)
            if buffer.format.isInterleaved {
                let source = data[0]
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += Float(source[frame * channels + channel])
                    }
                    mono[frame] = sum * intScale
                }
            } else {
                for channel in 0..<channels {
                    let source = data[channel]
                    for frame in 0..<frames {
                        mono[frame] += Float(source[frame]) * intScale
                    }
                }
            }
        } else {
            return nil
        }

        return mono
    }
}
