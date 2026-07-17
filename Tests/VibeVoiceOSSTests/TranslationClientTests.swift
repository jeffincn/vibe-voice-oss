import XCTest
@testable import VibeVoiceOSS

final class TranslationClientTests: XCTestCase {
    func testSanitizeStripsThinkTags() {
        let raw = "<think>long reasoning</think>\nAlright, I've added this feature."
        XCTAssertEqual(
            TranslationClient.sanitizeModelOutput(raw),
            "Alright, I've added this feature."
        )
    }

    func testSanitizeRejectsBareThinkingDump() {
        let raw = """
        Thinking Process:
        1.  **Analyze the Request:**
        - Input text: hello
        Drafting Translations:
        - Draft 1: Hi
        """
        XCTAssertEqual(TranslationClient.sanitizeModelOutput(raw), "")
    }

    func testSanitizeExtractsMarkedFinalTranslation() {
        let raw = """
        Thinking Process:
        lots of analysis here
        Final translation:
        Alright, I've added this feature. Let's see if it works.
        """
        XCTAssertEqual(
            TranslationClient.sanitizeModelOutput(raw),
            "Alright, I've added this feature. Let's see if it works."
        )
    }

    func testSanitizeModelNameKeepsFirstLine() {
        let messy = "Qwen3.6-35B-A3B-nvfp4\n\nqwen3.6-35B-A3B-nvfp4\n\n"
        XCTAssertEqual(
            TranslationClient.sanitizeModelName(messy),
            "Qwen3.6-35B-A3B-nvfp4"
        )
        XCTAssertEqual(
            TranslationClient.sanitizeModelName("  gemma-4-26b  "),
            "gemma-4-26b"
        )
    }

    func testModelsProbeURLStripsChatCompletions() {
        let chat = URL(string: "http://127.0.0.1:1234/v1/chat/completions")!
        XCTAssertEqual(
            TranslationClient.modelsProbeURL(from: chat).absoluteString,
            "http://127.0.0.1:1234/v1/models"
        )
    }
}
