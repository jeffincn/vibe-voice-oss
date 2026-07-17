import Foundation

/// Incremental resampler that keeps fractional state across audio tap buffers.
struct StreamingResampler: Sendable {
    private let outputRate: Double
    private var inputRate: Double
    /// Position within the pending input stream (0 = at `previous` when hasPrevious).
    private var position: Double = 0
    private var pending: [Float] = []

    init(inputRate: Double, outputRate: Double = Double(WAVEncoder.outputSampleRate)) {
        self.inputRate = max(1, inputRate)
        self.outputRate = max(1, outputRate)
    }

    mutating func updateInputRate(_ rate: Double) {
        let next = max(1, rate)
        if abs(next - inputRate) > 0.5 {
            inputRate = next
            position = 0
            pending.removeAll(keepingCapacity: true)
        }
    }

    mutating func reset() {
        position = 0
        pending.removeAll(keepingCapacity: true)
    }

    mutating func push(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if abs(inputRate - outputRate) < 0.5 {
            return samples
        }

        pending.append(contentsOf: samples)
        let scale = inputRate / outputRate
        var output: [Float] = []
        output.reserveCapacity(max(1, Int(Double(samples.count) * outputRate / inputRate) + 2))

        // Need one sample ahead for linear interpolation.
        while position + 1 < Double(pending.count) {
            let lowerIndex = Int(position)
            let upperIndex = lowerIndex + 1
            let t = Float(position - Double(lowerIndex))
            output.append(pending[lowerIndex] + (pending[upperIndex] - pending[lowerIndex]) * t)
            position += scale
        }

        // Drop consumed samples; keep last sample for next interpolation.
        let drop = max(0, Int(position) - 0)
        if drop > 0, drop < pending.count {
            pending.removeFirst(drop)
            position -= Double(drop)
        } else if drop >= pending.count, pending.count > 1 {
            let keep = pending[pending.count - 1]
            pending = [keep]
            position = max(0, position - Double(drop))
        }

        return output
    }

    static func int16LE(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        return data
    }
}
