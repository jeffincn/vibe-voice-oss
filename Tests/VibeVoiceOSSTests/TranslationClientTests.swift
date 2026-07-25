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

    func testCustomSystemPromptIsAppended() {
        let result = TranslationClient.withCustomSystemPrompt(
            "Base instructions", custom: "Use my writing style"
        )
        XCTAssertTrue(result.contains("Base instructions"))
        XCTAssertTrue(result.contains("Use my writing style"))
    }

    func testAuthHintAppendsNVIDIAGuidance() {
        let body = #"{"status":"401","title":"Unauthorized"}"#
        let hint = TranslationClient.authHintIfNeeded(
            status: 401,
            host: "integrate.api.nvidia.com",
            body: body,
            model: "nvidia/nemotron-3-ultra-550b-a55b"
        )
        XCTAssertTrue(hint.contains(body))
        XCTAssertTrue(hint.contains("NVIDIA"))
        XCTAssertTrue(hint.contains("Public API Endpoints"))
    }

    func testAuthHintSkipsNonAuthStatuses() {
        let body = "rate limited"
        XCTAssertEqual(
            TranslationClient.authHintIfNeeded(
                status: 429,
                host: "integrate.api.nvidia.com",
                body: body,
                model: "gpt-4o-mini"
            ),
            body
        )
    }

    func testApplyBearerTrimsWhitespace() {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        TranslationClient.applyBearerIfNeeded("  nvapi-abc  \n", to: &request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer nvapi-abc")
    }

    func testCredentialEndpointPolicyAllowsTLSAndLocalhostOnlyForCleartext() {
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: URL(string: "https://api.example.com/v1/chat/completions")!, apiKey: "key"
        ))
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: URL(string: "http://127.0.0.1:8000/v1/chat/completions")!, apiKey: "key"
        ))
        XCTAssertFalse(EndpointSecurity.allowsCredentialTransmission(
            to: URL(string: "http://192.168.1.20:8000/v1/chat/completions")!, apiKey: "key"
        ))
        XCTAssertTrue(EndpointSecurity.allowsCredentialTransmission(
            to: URL(string: "http://192.168.1.20:8000/v1/chat/completions")!, apiKey: ""
        ))
    }

    func testChatPayloadDelegatesToNemotronProfile() {
        let payload = TranslationClient.chatCompletionPayload(
            model: "nvidia/nemotron-3-ultra-550b-a55b",
            messages: [["role": "user", "content": "hi"]],
            temperature: 0.2,
            topP: 0.8,
            maxTokens: 1024
        )
        XCTAssertNil(payload["enable_thinking"])
        let kwargs = payload["chat_template_kwargs"] as? [String: Any]
        XCTAssertEqual(kwargs?["enable_thinking"] as? Bool, true)
        XCTAssertEqual(payload["reasoning_budget"] as? Int, 1024)
    }

    func testChatPayloadDelegatesToQwenProfile() {
        let payload = TranslationClient.chatCompletionPayload(
            model: "Qwen3.5-35B",
            messages: [["role": "user", "content": "hi"]],
            temperature: 0.2,
            topP: 0.8,
            maxTokens: 64
        )
        XCTAssertEqual(payload["enable_thinking"] as? Bool, false)
        let kwargs = payload["chat_template_kwargs"] as? [String: Any]
        XCTAssertEqual(kwargs?["enable_thinking"] as? Bool, false)
    }
}
