import XCTest
@testable import VibeVoiceOSS

@MainActor
final class AppSettingsTests: XCTestCase {
    func testDefaultsUseIntegratedASRAndDisableLLMPostProcessing() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.asrBackend, .integrated)
        XCTAssertEqual(settings.integratedASREngine, .whisperMLX)
        XCTAssertEqual(settings.whisperKitModel, IntegratedASREngine.whisperMLX.defaultModel)
        XCTAssertTrue(settings.model.isEmpty)
        XCTAssertEqual(settings.llmBackend, .disabled)
        XCTAssertFalse(settings.llmFeaturesAvailable)
        XCTAssertFalse(settings.effectiveTargetLanguage.translates)
    }

    func testLLMApiModeRequiresEndpointAndModel() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.llmBackend = .api
        settings.llmEndpoint = "http://127.0.0.1:8000/v1/chat/completions"
        settings.translationModel = ""
        XCTAssertFalse(settings.llmFeaturesAvailable)

        settings.translationModel = "qwen-chat"
        XCTAssertTrue(settings.llmFeaturesAvailable)
    }

    func testEffectiveTargetFallsBackToOriginalWhenLLMUnavailable() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.targetLanguageID = "zh-Hans"
        XCTAssertTrue(settings.targetLanguage.translates)
        XCTAssertFalse(settings.effectiveTargetLanguage.translates)

        settings.llmBackend = .api
        settings.llmEndpoint = "http://127.0.0.1:8000/v1/chat/completions"
        settings.translationModel = "qwen-chat"
        XCTAssertEqual(settings.effectiveTargetLanguage.id, "zh-Hans")
    }

    func testWhisperKitModelMigrationDropsRepoPrefix() {
        let defaults = isolatedDefaults()
        defaults.set("openai_whisper-large-v3-v20240930_626MB", forKey: "whisperKitModel")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.whisperKitModel, "large-v3-v20240930_626MB")
        XCTAssertEqual(defaults.string(forKey: "whisperKitModel"), "large-v3-v20240930_626MB")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "VibeVoiceOSS.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
