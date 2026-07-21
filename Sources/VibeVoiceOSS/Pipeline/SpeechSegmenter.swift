import Foundation

enum SpeechSegmenterPhase: Equatable, Sendable {
    case idle
    case possibleSpeech
    case speaking
    case possibleEnd
    case completed
}

struct SpeechSegmenterConfig: Sendable {
    /// Probability above which speech is considered active.
    var speechThreshold: Float = 0.45
    /// Probability below which silence is considered.
    var silenceThreshold: Float = 0.28
    /// Prepend this much audio when a segment starts (seconds @ 16 kHz).
    var preRollSeconds: Double = 0.30
    /// Append this much audio after endpoint (seconds).
    var postRollSeconds: Double = 0.20
    /// Ignore bursts shorter than this.
    var minimumSpeechSeconds: Double = 0.20
    /// Force-complete if continuous speech exceeds this.
    var maximumSpeechSeconds: Double = 8.0
    /// How long silence must last in PossibleEnd before completing.
    var endpointTimeoutSeconds: Double = 0.55
    /// How long speech must stay above threshold to leave Idle.
    var speechOnsetSeconds: Double = 0.10

    var sampleRate: Double = 16_000

    var preRollSamples: Int { Int(preRollSeconds * sampleRate) }
    var postRollSamples: Int { Int(postRollSeconds * sampleRate) }
    var minimumSpeechSamples: Int { Int(minimumSpeechSeconds * sampleRate) }
    var maximumSpeechSamples: Int { Int(maximumSpeechSeconds * sampleRate) }
    var endpointTimeoutSamples: Int { Int(endpointTimeoutSeconds * sampleRate) }
    var speechOnsetSamples: Int { Int(speechOnsetSeconds * sampleRate) }
}

struct SpeechSegment: Sendable {
    let samples: [Float]
    let durationSeconds: Double
}

/// State machine: Idle → PossibleSpeech → Speaking → PossibleEnd → Completed → Idle.
final class SpeechSegmenter: @unchecked Sendable {
    private let config: SpeechSegmenterConfig
    private let lock = NSLock()
    private var phase: SpeechSegmenterPhase = .idle
    private var onsetSamples = 0
    private var speechSamples = 0
    private var silenceSamples = 0
    private var segmentStartIndex = 0
    /// Absolute sample counter for the continuous 16 kHz stream.
    private var absoluteSampleCount = 0
    private var ring: AudioRingBuffer

    var currentPhase: SpeechSegmenterPhase {
        lock.withLock { phase }
    }

    init(config: SpeechSegmenterConfig = SpeechSegmenterConfig()) {
        self.config = config
        // Keep ~30s of audio for long utterances + pre-roll.
        ring = AudioRingBuffer(capacity: Int(config.sampleRate * 30))
    }

    func reset() {
        lock.withLock {
            phase = .idle
            onsetSamples = 0
            speechSamples = 0
            silenceSamples = 0
            segmentStartIndex = 0
            absoluteSampleCount = 0
            ring.reset()
        }
    }

    /// Feed 16 kHz mono samples and the latest VAD probability.
    /// Returns a completed segment when the state machine transitions to Completed.
    func push(samples: [Float], speechProbability: Float) -> SpeechSegment? {
        guard !samples.isEmpty else { return nil }

        return lock.withLock {
            ring.append(samples)
            absoluteSampleCount += samples.count
            let isSpeech = speechProbability >= config.speechThreshold
            let isSilence = speechProbability <= config.silenceThreshold

            switch phase {
            case .idle:
                if isSpeech {
                    onsetSamples += samples.count
                    if onsetSamples >= config.speechOnsetSamples {
                        phase = .possibleSpeech
                        SpeechPipelineLog.segmenter.debug("idle → possibleSpeech p=\(speechProbability, format: .fixed(precision: 2))")
                    }
                } else {
                    onsetSamples = 0
                }

            case .possibleSpeech:
                if isSpeech {
                    speechSamples += samples.count
                    if speechSamples >= config.minimumSpeechSamples {
                        let preRoll = config.preRollSamples
                        segmentStartIndex = max(0, absoluteSampleCount - speechSamples - preRoll)
                        phase = .speaking
                        SpeechPipelineLog.segmenter.debug("possibleSpeech → speaking")
                    }
                } else if isSilence {
                    phase = .idle
                    onsetSamples = 0
                    speechSamples = 0
                }
                // Mid-band hysteresis: hold PossibleSpeech, do not reset.

            case .speaking:
                speechSamples += samples.count
                if isSilence {
                    silenceSamples = samples.count
                    phase = .possibleEnd
                    SpeechPipelineLog.segmenter.debug("speaking → possibleEnd")
                } else {
                    silenceSamples = 0
                    // Force-finalize very long utterances so ASR can run.
                    if speechSamples >= config.maximumSpeechSamples {
                        let exported = exportSegment(length: speechSamples + config.postRollSamples)
                        phase = .idle
                        onsetSamples = 0
                        speechSamples = 0
                        silenceSamples = 0
                        SpeechPipelineLog.segmenter.info(
                            "speaking → completed (max duration) duration=\(Double(exported.count) / self.config.sampleRate, format: .fixed(precision: 2))s"
                        )
                        return SpeechSegment(
                            samples: exported,
                            durationSeconds: Double(exported.count) / config.sampleRate
                        )
                    }
                }

            case .possibleEnd:
                if isSpeech {
                    silenceSamples = 0
                    speechSamples += samples.count
                    phase = .speaking
                    SpeechPipelineLog.segmenter.debug("possibleEnd → speaking (short pause)")
                } else {
                    silenceSamples += samples.count
                    if silenceSamples >= config.endpointTimeoutSamples {
                        let postRoll = config.postRollSamples
                        let endIndex = absoluteSampleCount + postRoll
                        let length = max(0, endIndex - segmentStartIndex)
                        let exported = exportSegment(length: length)
                        phase = .completed
                        SpeechPipelineLog.segmenter.info(
                            "possibleEnd → completed duration=\(Double(exported.count) / self.config.sampleRate, format: .fixed(precision: 2))s"
                        )
                        let segment = SpeechSegment(
                            samples: exported,
                            durationSeconds: Double(exported.count) / self.config.sampleRate
                        )
                        // Reset for next utterance while staying Completed briefly for caller.
                        phase = .idle
                        onsetSamples = 0
                        speechSamples = 0
                        silenceSamples = 0
                        return segment
                    }
                }

            case .completed:
                phase = .idle
            }

            return nil
        }
    }

    private func exportSegment(length: Int) -> [Float] {
        let all = ring.snapshot()
        let take = min(length, all.count)
        guard take > 0 else { return [] }
        return Array(all.suffix(take))
    }
}
