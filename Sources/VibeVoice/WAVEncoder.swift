import Foundation

enum WAVEncoder {
    static let outputSampleRate = 16_000

    static func encode(samples: [Float], inputSampleRate: Double) -> Data {
        let resampled = resample(samples: samples, from: inputSampleRate, to: Double(outputSampleRate))
        var pcm = Data(capacity: resampled.count * 2)

        for sample in resampled {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }

        var output = Data()
        output.appendASCII("RIFF")
        output.appendUInt32(UInt32(36 + pcm.count))
        output.appendASCII("WAVE")
        output.appendASCII("fmt ")
        output.appendUInt32(16)
        output.appendUInt16(1)
        output.appendUInt16(1)
        output.appendUInt32(UInt32(outputSampleRate))
        output.appendUInt32(UInt32(outputSampleRate * 2))
        output.appendUInt16(2)
        output.appendUInt16(16)
        output.appendASCII("data")
        output.appendUInt32(UInt32(pcm.count))
        output.append(pcm)
        return output
    }

    static func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard !samples.isEmpty, inputRate > 0, outputRate > 0 else { return [] }
        guard abs(inputRate - outputRate) > 0.5 else { return samples }

        let outputCount = max(1, Int((Double(samples.count) * outputRate / inputRate).rounded()))
        let scale = inputRate / outputRate

        return (0..<outputCount).map { index in
            let sourcePosition = Double(index) * scale
            let lower = min(Int(sourcePosition), samples.count - 1)
            let upper = min(lower + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            return samples[lower] + (samples[upper] - samples[lower]) * fraction
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
