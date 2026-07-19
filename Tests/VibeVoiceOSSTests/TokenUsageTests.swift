import XCTest
@testable import VibeVoiceOSS

final class TokenUsageTests: XCTestCase {
    func testParsesChatUsageAndDetailsWithoutDoubleCounting() {
        let raw: [String: Any] = [
            "prompt_tokens": 100,
            "completion_tokens": 40,
            "total_tokens": 140,
            "prompt_tokens_details": ["cached_tokens": 60, "audio_tokens": 20],
            "completion_tokens_details": ["reasoning_tokens": 12, "audio_tokens": 5]
        ]
        let usage = TokenUsage.parse(raw)
        XCTAssertEqual(usage?.inputTokens, 100)
        XCTAssertEqual(usage?.outputTokens, 40)
        XCTAssertEqual(usage?.totalTokens, 140)
        XCTAssertEqual(usage?.cachedInputTokens, 60)
        XCTAssertEqual(usage?.reasoningTokens, 12)
        XCTAssertEqual(usage?.audioInputTokens, 20)
        XCTAssertEqual(usage?.audioOutputTokens, 5)
    }

    func testParsesDurationUsage() {
        let usage = TokenUsage.parse(["type": "duration", "seconds": 12.5])
        XCTAssertEqual(usage?.audioSeconds, 12.5)
        XCTAssertEqual(usage?.totalTokens, 0)
    }

    func testParsesAggregatedAudioFields() {
        let usage = TokenUsage.parse([
            "input_tokens": 20,
            "output_tokens": 8,
            "input_audio_tokens": 12,
            "output_audio_tokens": 4
        ])
        XCTAssertEqual(usage?.audioInputTokens, 12)
        XCTAssertEqual(usage?.audioOutputTokens, 4)
    }

    func testFallsBackToCalculatedTotal() {
        let usage = TokenUsage.parse(["input_tokens": 8, "output_tokens": 3])
        XCTAssertEqual(usage?.totalTokens, 11)
    }
}
