import Foundation

/// Multi-band energy for HUD rhythm (ported from fluid-voice AudioAnalyser semantics).
struct AudioBands: Equatable, Sendable {
    var lowMid: Float
    var mid: Float
    var high: Float
    var overall: Float

    static let silent = AudioBands(lowMid: 0, mid: 0, high: 0, overall: 0)

    var primaryLevel: Float { overall }
}

enum AudioBandEstimator {
    /// Lightweight time-domain bands from a mono float buffer (no FFT).
    /// Uses block energy + simple high-pass residual split so HUD stays cheap on the audio tap.
    static func estimate(samples: [Float]) -> AudioBands {
        guard !samples.isEmpty else { return .silent }

        var sumSquares: Float = 0
        var highSquares: Float = 0
        var previous: Float = 0
        for sample in samples {
            sumSquares += sample * sample
            let high = sample - previous
            highSquares += high * high
            previous = sample
        }
        let count = Float(samples.count)
        let rms = sqrt(sumSquares / count)
        let highRMS = sqrt(highSquares / count)

        let overall = normalizeDB(rms)
        let high = normalizeDB(highRMS)
        // Mid tracks overall with a slight lift; lowMid is the softer remainder.
        let mid = min(1, overall * 0.85 + high * 0.15)
        let lowMid = max(0, overall * 0.7 - high * 0.25)

        return AudioBands(
            lowMid: lowMid,
            mid: mid,
            high: high,
            overall: overall * 0.38 + mid * 0.44 + high * 0.18
        )
    }

    private static func normalizeDB(_ rms: Float) -> Float {
        let decibels = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, (decibels + 45) / 37))
    }

    static func follow(current: AudioBands, target: AudioBands, attack: Float = 0.55, release: Float = 0.22) -> AudioBands {
        func step(_ c: Float, _ t: Float) -> Float {
            let rate = t > c ? attack : release
            return c + (t - c) * rate
        }
        return AudioBands(
            lowMid: step(current.lowMid, target.lowMid),
            mid: step(current.mid, target.mid),
            high: step(current.high, target.high),
            overall: step(current.overall, target.overall)
        )
    }
}
