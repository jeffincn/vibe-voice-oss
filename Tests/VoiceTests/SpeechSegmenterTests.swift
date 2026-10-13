import XCTest
@testable import VibeVoiceOSS

final class SpeechSegmenterTests: XCTestCase {
    /// Same shape as the shipping config, scaled down so a test can push a whole
    /// utterance in a few dozen blocks.
    private static func config(maximumSpeechSeconds: Double = 4.0) -> SpeechSegmenterConfig {
        var config = SpeechSegmenterConfig()
        config.speechOnsetSeconds = 0.032
        config.minimumSpeechSeconds = 0.064
        config.endpointTimeoutSeconds = 0.192
        config.preRollSeconds = 0.032
        config.postRollSeconds = 0.032
        config.maximumSpeechSeconds = maximumSpeechSeconds
        return config
    }

    private static let block = [Float](repeating: 0.1, count: 512)
    private static let speech: Float = 0.9
    private static let silence: Float = 0.05

    @discardableResult
    private func push(
        _ segmenter: SpeechSegmenter,
        blocks: Int,
        probability: Float,
        into collected: inout [SpeechSegment]
    ) -> [SpeechSegment] {
        for _ in 0..<blocks {
            if let segment = segmenter.push(samples: Self.block, speechProbability: probability) {
                collected.append(segment)
            }
        }
        return collected
    }

    func testSilenceNeverProducesASegment() {
        let segmenter = SpeechSegmenter(config: Self.config())
        var segments: [SpeechSegment] = []
        push(segmenter, blocks: 60, probability: Self.silence, into: &segments)
        XCTAssertTrue(segments.isEmpty)
        XCTAssertEqual(segmenter.currentPhase, .idle)
    }

    func testSpeechFollowedBySilenceCompletesOneSegment() {
        let segmenter = SpeechSegmenter(config: Self.config())
        var segments: [SpeechSegment] = []
        push(segmenter, blocks: 16, probability: Self.speech, into: &segments)
        XCTAssertTrue(segments.isEmpty, "a segment should not close while speech is ongoing")
        push(segmenter, blocks: 12, probability: Self.silence, into: &segments)

        XCTAssertEqual(segments.count, 1)
        let segment = segments[0]
        // 16 blocks of speech is 0.512 s; pre-roll, the trailing silence that had to
        // elapse before the endpoint fired, and post-roll all land inside the segment.
        XCTAssertGreaterThan(segment.durationSeconds, 0.5)
        XCTAssertEqual(segment.durationSeconds, Double(segment.samples.count) / 16_000, accuracy: 1e-9)
        XCTAssertEqual(segmenter.currentPhase, .idle)
    }

    func testBurstShorterThanTheMinimumIsDiscarded() {
        let segmenter = SpeechSegmenter(config: Self.config())
        var segments: [SpeechSegment] = []
        // Enough to leave idle, not enough to reach the minimum speech length.
        push(segmenter, blocks: 2, probability: Self.speech, into: &segments)
        XCTAssertEqual(segmenter.currentPhase, .possibleSpeech)
        push(segmenter, blocks: 12, probability: Self.silence, into: &segments)

        XCTAssertTrue(segments.isEmpty)
        XCTAssertEqual(segmenter.currentPhase, .idle)
    }

    func testShortPauseDoesNotSplitAnUtterance() {
        let segmenter = SpeechSegmenter(config: Self.config())
        var segments: [SpeechSegment] = []
        push(segmenter, blocks: 10, probability: Self.speech, into: &segments)
        // Shorter than the endpoint timeout — a breath, not the end of a sentence.
        push(segmenter, blocks: 3, probability: Self.silence, into: &segments)
        XCTAssertEqual(segmenter.currentPhase, .possibleEnd)
        push(segmenter, blocks: 10, probability: Self.speech, into: &segments)
        XCTAssertEqual(segmenter.currentPhase, .speaking)
        XCTAssertTrue(segments.isEmpty)

        push(segmenter, blocks: 12, probability: Self.silence, into: &segments)
        XCTAssertEqual(segments.count, 1, "the pause should not have closed a segment of its own")
    }

    func testUninterruptedSpeechIsForceCompletedAtTheMaximum() {
        let segmenter = SpeechSegmenter(config: Self.config(maximumSpeechSeconds: 0.5))
        var segments: [SpeechSegment] = []
        push(segmenter, blocks: 40, probability: Self.speech, into: &segments)

        XCTAssertFalse(segments.isEmpty, "ASR would never run on an utterance that never ends")
        XCTAssertGreaterThanOrEqual(segments[0].durationSeconds, 0.5)
    }

    func testResetDropsBufferedAudioAndReturnsToIdle() {
        let segmenter = SpeechSegmenter(config: Self.config())
        var segments: [SpeechSegment] = []
        push(segmenter, blocks: 10, probability: Self.speech, into: &segments)
        segmenter.reset()
        XCTAssertEqual(segmenter.currentPhase, .idle)

        push(segmenter, blocks: 12, probability: Self.silence, into: &segments)
        XCTAssertTrue(segments.isEmpty, "audio from before the reset must not resurface")
    }

    func testEmptyBlocksAreIgnored() {
        let segmenter = SpeechSegmenter(config: Self.config())
        XCTAssertNil(segmenter.push(samples: [], speechProbability: Self.speech))
        XCTAssertEqual(segmenter.currentPhase, .idle)
    }

    func testProbabilitiesBetweenTheThresholdsHoldTheCurrentPhase() {
        let config = Self.config()
        let segmenter = SpeechSegmenter(config: config)
        var segments: [SpeechSegment] = []
        push(segmenter, blocks: 2, probability: Self.speech, into: &segments)
        XCTAssertEqual(segmenter.currentPhase, .possibleSpeech)

        // Above the silence threshold but below the speech threshold: hysteresis
        // keeps the segmenter where it is rather than flapping back to idle.
        let ambiguous = (config.speechThreshold + config.silenceThreshold) / 2
        push(segmenter, blocks: 10, probability: ambiguous, into: &segments)
        XCTAssertEqual(segmenter.currentPhase, .possibleSpeech)
        XCTAssertTrue(segments.isEmpty)
    }
}
