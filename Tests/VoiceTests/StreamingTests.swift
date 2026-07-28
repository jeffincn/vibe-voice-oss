import XCTest
@testable import VibeVoiceOSS

final class TranscriptAccumulatorTests: XCTestCase {
    func testPartialThenFinalReplacesDisplay() {
        var acc = TranscriptAccumulator()
        acc.applyPartial("你好世")
        XCTAssertEqual(acc.displayText, "你好世")
        XCTAssertFalse(acc.isFinalized)

        acc.applyPartial("你好世界")
        XCTAssertEqual(acc.displayText, "你好世界")

        let final = acc.applyFinal("你好，世界。")
        XCTAssertEqual(final, "你好，世界。")
        XCTAssertEqual(acc.displayText, "你好，世界。")
        XCTAssertTrue(acc.isFinalized)
        XCTAssertTrue(acc.unstableSuffix.isEmpty)
    }

    func testStablePrefixAndUnstableSuffix() {
        var acc = TranscriptAccumulator()
        acc.applyStable("今天")
        acc.applyPartial("天气不错")
        XCTAssertEqual(acc.stablePrefix, "今天")
        XCTAssertEqual(acc.unstableSuffix, "天气不错")
        XCTAssertEqual(acc.displayText, "今天天气不错")
    }

    func testSoftGrowthDoesNotShrinkUnnecessarily() {
        var acc = TranscriptAccumulator()
        acc.applyPartial("hello")
        acc.applyPartial("hello world")
        XCTAssertEqual(acc.unstableSuffix, "hello world")
        acc.applyPartial("") // clear live tail after commit
        XCTAssertEqual(acc.unstableSuffix, "")
    }

    func testLatinStableJoinsWithSpace() {
        var acc = TranscriptAccumulator()
        acc.applyStable("Hello")
        acc.applyPartial("world")
        XCTAssertEqual(acc.displayText, "Hello world")
    }

    func testFinalIgnoresLaterPartials() {
        var acc = TranscriptAccumulator()
        _ = acc.applyFinal("锁定")
        acc.applyPartial("不应出现")
        acc.applyStable("也不应")
        XCTAssertEqual(acc.displayText, "锁定")
    }

    func testDivergenceFlagWhenFinalDisagrees() {
        var acc = TranscriptAccumulator()
        acc.applyStable("原始前缀")
        _ = acc.applyFinal("完全不同的最终结果")
        XCTAssertTrue(acc.divergedFromStable)
    }

    func testResetClearsState() {
        var acc = TranscriptAccumulator()
        acc.applyPartial("abc")
        _ = acc.applyFinal("abc")
        acc.reset()
        XCTAssertEqual(acc.displayText, "")
        XCTAssertFalse(acc.isFinalized)
        XCTAssertFalse(acc.divergedFromStable)
    }
}

final class StreamingResamplerTests: XCTestCase {
    func testPassthroughWhenRatesMatch() {
        var resampler = StreamingResampler(inputRate: 16_000, outputRate: 16_000)
        let input: [Float] = [0, 0.5, -0.5, 1]
        XCTAssertEqual(resampler.push(input), input)
    }

    func testDownsampleProducesExpectedLength() {
        var resampler = StreamingResampler(inputRate: 48_000, outputRate: 16_000)
        let input = [Float](repeating: 0.1, count: 4_800) // 100 ms @ 48 kHz
        let output = resampler.push(input)
        // Allow a few samples of streaming edge slack.
        XCTAssertGreaterThan(output.count, 1_500)
        XCTAssertLessThan(output.count, 1_700)
    }

    /// RMS of a tone after 48 kHz → 16 kHz conversion, skipping the filter's settling.
    private func downsampledRMS(toneHz: Double) -> Float {
        var resampler = StreamingResampler(inputRate: 48_000, outputRate: 16_000)
        let input = (0..<48_000).map { index in
            Float(sin(2 * Double.pi * toneHz * Double(index) / 48_000))
        }
        let output = resampler.push(input)
        let settled = output.dropFirst(2_000)
        let meanSquare = settled.reduce(Float.zero) { $0 + $1 * $1 } / Float(settled.count)
        return sqrt(meanSquare)
    }

    func testSpeechBandSurvivesDownsampling() {
        XCTAssertEqual(downsampledRMS(toneHz: 1_000), 0.707, accuracy: 0.03)
    }

    func testContentAboveNyquistIsRemovedBeforeItCanFold() {
        // 12 kHz would alias to 4 kHz — squarely inside the speech band — if it reached
        // the decimator. Linear interpolation alone barely touches it.
        let aliasing = downsampledRMS(toneHz: 12_000)
        XCTAssertLessThan(aliasing, 0.1, "expected roughly -23 dB, got \(aliasing)")
    }

    func testInt16EncodingRoundTripScale() {
        let data = StreamingResampler.int16LE(from: [0, 1, -1])
        XCTAssertEqual(data.count, 6)
        let values: [Int16] = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Int16.self)).map { Int16(littleEndian: $0) }
        }
        XCTAssertEqual(values[0], 0)
        XCTAssertEqual(values[1], Int16.max)
        XCTAssertEqual(values[2], -Int16.max)
    }
}

final class AudioBandsTests: XCTestCase {
    func testSilenceIsNearZero() {
        let bands = AudioBandEstimator.estimate(samples: [Float](repeating: 0, count: 1_024))
        XCTAssertEqual(bands.overall, 0, accuracy: 0.02)
    }

    func testLoudToneRaisesOverall() {
        let samples = (0..<1_024).map { index -> Float in
            sin(Float(index) * 0.2) * 0.4
        }
        let bands = AudioBandEstimator.estimate(samples: samples)
        XCTAssertGreaterThan(bands.overall, 0.2)
    }

    func testFollowSmoothsAttack() {
        let current = AudioBands.silent
        let target = AudioBands(lowMid: 1, mid: 1, high: 1, overall: 1)
        let next = AudioBandEstimator.follow(current: current, target: target, attack: 0.5, release: 0.2)
        XCTAssertEqual(next.overall, 0.5, accuracy: 0.001)
    }
}

@MainActor
final class StreamingModeAndTimingTests: XCTestCase {
    func testMarkFirstPartialOnce() async throws {
        let store = StageTimingStore()
        store.beginSession()
        store.enter(.recording)
        try await Task.sleep(for: .milliseconds(25))
        store.markFirstPartial()
        try await Task.sleep(for: .milliseconds(20))
        store.markFirstPartial() // ignored
        store.enter(.finalizing)
        store.finishSession(outcome: .success)

        let session = try XCTUnwrap(store.latestSession)
        let first = try XCTUnwrap(session.firstPartialMs)
        XCTAssertGreaterThanOrEqual(first, 20)
        XCTAssertEqual(session.stages.map(\.stage), [.recording, .finalizing])
    }

    func testStreamingModeLabels() {
        XCTAssertTrue(StreamingMode.duplexStreaming.usesLivePartialsWhileRecording)
        XCTAssertFalse(StreamingMode.sseResult.usesLivePartialsWhileRecording)
        XCTAssertFalse(StreamingMode.batch.usesLivePartialsWhileRecording)
        XCTAssertTrue(StreamingMode.batch.caption.contains("实时字幕"))
    }
}
