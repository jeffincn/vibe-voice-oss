import Foundation

/// Incremental resampler that keeps fractional state across audio tap buffers.
struct StreamingResampler: Sendable {
    private let outputRate: Double
    private var inputRate: Double
    /// Position within the pending input stream (0 = at `previous` when hasPrevious).
    private var position: Double = 0
    private var pending: [Float] = []
    private var antiAlias: AntiAliasFilter?

    init(inputRate: Double, outputRate: Double = Double(WAVEncoder.outputSampleRate)) {
        self.inputRate = max(1, inputRate)
        self.outputRate = max(1, outputRate)
        antiAlias = AntiAliasFilter(inputRate: self.inputRate, outputRate: self.outputRate)
    }

    mutating func updateInputRate(_ rate: Double) {
        let next = max(1, rate)
        if abs(next - inputRate) > 0.5 {
            inputRate = next
            position = 0
            pending.removeAll(keepingCapacity: true)
            antiAlias = AntiAliasFilter(inputRate: inputRate, outputRate: outputRate)
        }
    }

    mutating func reset() {
        position = 0
        pending.removeAll(keepingCapacity: true)
        antiAlias?.reset()
    }

    mutating func push(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if abs(inputRate - outputRate) < 0.5 {
            return samples
        }

        // Band-limit before decimating. Linear interpolation on its own barely attenuates
        // above the new Nyquist, so 48 kHz content at 10 kHz used to fold back to 6 kHz —
        // sibilance, fan hum and keyboard clicks landing right where speech lives.
        pending.append(contentsOf: antiAlias?.filtered(samples) ?? samples)
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

    /// Fourth-order Butterworth low-pass, run over the input stream before decimation.
    ///
    /// Two cascaded biquads at the Butterworth Q pair. Cutoff sits at 45% of the output
    /// rate — 7.2 kHz for a 16 kHz target — which keeps everything speech recognition
    /// uses and leaves a transition band before the new Nyquist.
    struct AntiAliasFilter: Sendable {
        private var sections: [Biquad]

        /// Nil unless the conversion actually decimates; upsampling needs no filter.
        init?(inputRate: Double, outputRate: Double) {
            guard inputRate > outputRate + 0.5 else { return nil }
            let cutoff = 0.45 * outputRate
            sections = [0.541_196_10, 1.306_562_96].map {
                Biquad(cutoff: cutoff, sampleRate: inputRate, q: $0)
            }
        }

        mutating func reset() {
            for index in sections.indices {
                sections[index].reset()
            }
        }

        mutating func filtered(_ samples: [Float]) -> [Float] {
            var output = samples
            for index in sections.indices {
                sections[index].process(&output)
            }
            return output
        }
    }

    /// Direct Form II transposed biquad, from the RBJ low-pass cookbook.
    struct Biquad: Sendable {
        private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
        private var z1: Float = 0, z2: Float = 0

        init(cutoff: Double, sampleRate: Double, q: Double) {
            // Keep the cutoff strictly inside the Nyquist limit; tan() blows up at it.
            let normalized = min(max(cutoff / sampleRate, 0.000_1), 0.49)
            let w0 = 2 * Double.pi * normalized
            let alpha = sin(w0) / (2 * q)
            let cosW0 = cos(w0)
            let a0 = 1 + alpha
            b0 = Float((1 - cosW0) / 2 / a0)
            b1 = Float((1 - cosW0) / a0)
            b2 = Float((1 - cosW0) / 2 / a0)
            a1 = Float(-2 * cosW0 / a0)
            a2 = Float((1 - alpha) / a0)
        }

        mutating func reset() {
            z1 = 0
            z2 = 0
        }

        mutating func process(_ samples: inout [Float]) {
            for index in samples.indices {
                let input = samples[index]
                let output = b0 * input + z1
                z1 = b1 * input - a1 * output + z2
                z2 = b2 * input - a2 * output
                samples[index] = output
            }
        }
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
