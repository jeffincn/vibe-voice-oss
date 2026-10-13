import XCTest
@testable import VibeVoiceOSS

final class LLMProviderProfileTests: XCTestCase {
    func testResolveNemotronByModelName() {
        let profile = LLMProviderProfile.resolve(
            endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
            model: "nvidia/nemotron-3-ultra-550b-a55b"
        )
        XCTAssertEqual(profile.kind, .nvidiaNemotron)
    }

    func testResolveQwenByModelName() {
        let profile = LLMProviderProfile.resolve(
            endpoint: "http://127.0.0.1:1234/v1/chat/completions",
            model: "Qwen3.5-35B"
        )
        XCTAssertEqual(profile.kind, .qwen)
    }

    func testResolveOpenAICompatibleByDefault() {
        let profile = LLMProviderProfile.resolve(
            endpoint: "https://api.openai.com/v1/chat/completions",
            model: "gpt-4o-mini"
        )
        XCTAssertEqual(profile.kind, .openaiCompatible)
    }

    func testNVIDIALlamaStaysOpenAICompatible() {
        // Non-Nemotron models on Integrate still use the vanilla body.
        let profile = LLMProviderProfile.resolve(
            endpoint: "https://integrate.api.nvidia.com/v1/chat/completions",
            model: "meta/llama-3.1-70b-instruct"
        )
        XCTAssertEqual(profile.kind, .openaiCompatible)
    }

    func testOpenAIPayloadHasOnlyStandardFields() {
        let payload = LLMProviderProfile(kind: .openaiCompatible).chatCompletionPayload(
            model: "gpt-4o-mini",
            messages: [["role": "user", "content": "hi"]],
            temperature: 0.2,
            topP: 0.8,
            maxTokens: 64
        )
        XCTAssertEqual(Set(payload.keys), ["model", "temperature", "top_p", "max_tokens", "messages"])
    }

    func testQwenPayloadDisablesThinking() {
        let payload = LLMProviderProfile(kind: .qwen).chatCompletionPayload(
            model: "Qwen3.5-35B",
            messages: [["role": "user", "content": "hi"]],
            temperature: 0.2,
            topP: 0.8,
            maxTokens: 64
        )
        XCTAssertEqual(payload["enable_thinking"] as? Bool, false)
        let kwargs = payload["chat_template_kwargs"] as? [String: Any]
        XCTAssertEqual(kwargs?["enable_thinking"] as? Bool, false)
        XCTAssertNil(payload["reasoning_budget"])
    }

    func testNemotronPayloadMatchesOfficialExtraBody() {
        let payload = LLMProviderProfile(kind: .nvidiaNemotron).chatCompletionPayload(
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
        XCTAssertEqual(payload["max_tokens"] as? Int, 2048)
        XCTAssertEqual(payload["top_p"] as? Double, 0.95)
        XCTAssertGreaterThanOrEqual(payload["temperature"] as? Double ?? 0, 0.6)
    }

    func testNemotronProbeSampling() {
        let probe = LLMProviderProfile(kind: .nvidiaNemotron).probeSampling
        XCTAssertEqual(probe.temperature, 1.0)
        XCTAssertEqual(probe.topP, 0.95)
        XCTAssertEqual(probe.maxTokens, 64)
    }

    func testAuthHintForNemotronValidation() {
        let hint = LLMProviderProfile(kind: .nvidiaNemotron).authHint(
            status: 400,
            host: "integrate.api.nvidia.com",
            body: #"{"error":{"message":"Validation: Unsupported..."}}"#
        )
        XCTAssertTrue(hint.contains("reasoning_budget"))
        XCTAssertTrue(hint.contains("NVIDIA Nemotron"))
    }

    func testAuthHintForNVIDIAUnauthorized() {
        let hint = LLMProviderProfile(kind: .openaiCompatible).authHint(
            status: 401,
            host: "integrate.api.nvidia.com",
            body: #"{"status":"401","title":"Unauthorized"}"#
        )
        XCTAssertTrue(hint.contains("Public API Endpoints"))
    }
}
