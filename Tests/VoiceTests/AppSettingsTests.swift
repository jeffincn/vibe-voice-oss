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
        // API keys/models can be present in the developer Keychain; the explicit backend
        // preference still controls whether LLM processing is enabled for this suite.
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

    func testOutputLanguagesLimitTranslationsToThreeAndKeepOriginalSeparate() {
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.setTargetLanguageSelected(TargetLanguage.resolve(id: "ko"), selected: true)
        settings.setTargetLanguageSelected(TargetLanguage.resolve(id: "fr"), selected: true)
        settings.setTargetLanguageSelected(TargetLanguage.resolve(id: "es"), selected: true)
        settings.setTargetLanguageSelected(TargetLanguage.resolve(id: "hi"), selected: true)

        XCTAssertEqual(settings.targetLanguageIDs, ["ko", "fr", "es"])
        XCTAssertEqual(settings.targetLanguages.map(\.id), ["ko", "fr", "es"])
        XCTAssertFalse(settings.canSelectMoreTargetLanguages)
        XCTAssertFalse(settings.includeOriginalOutput)
        XCTAssertEqual(settings.outputLanguageSummary, "韩语（한국어） + 法语（Français） + 西班牙语（Español）")
    }

    func testOriginalCanBeAddedOrRemovedIndependentlyFromTranslations() {
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.setTargetLanguageSelected(TargetLanguage.resolve(id: "zh-Hans"), selected: true)

        XCTAssertFalse(settings.includeOriginalOutput)
        XCTAssertEqual(settings.outputLanguageSummary, "简体中文")

        settings.setIncludeOriginalOutput(true)
        XCTAssertEqual(settings.outputLanguageSummary, "原文 + 简体中文")

        settings.setIncludeOriginalOutput(false)
        XCTAssertEqual(settings.outputLanguageSummary, "简体中文")
    }

    func testOriginalOnlyCannotBeDisabledWithoutATranslation() {
        let settings = AppSettings(defaults: isolatedDefaults())
        settings.setIncludeOriginalOutput(false)

        XCTAssertTrue(settings.includeOriginalOutput)
        XCTAssertEqual(settings.outputLanguageSummary, "仅原文")
    }

    func testLegacyBilingualPreferenceMigratesToOneTranslationTarget() {
        let defaults = isolatedDefaults()
        defaults.set("bi-ja", forKey: "targetLanguageID")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.targetLanguageIDs, ["ja"])
        XCTAssertEqual(defaults.stringArray(forKey: "targetLanguageIDs"), ["ja"])
    }

    func testHFEndpointPersistsAndFlowsIntoConfiguration() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.hfEndpoint.isEmpty)
        XCTAssertNil(settings.configuration.normalizedHFEndpoint)

        settings.hfEndpoint = "https://hf-mirror.com/"
        XCTAssertEqual(settings.configuration.normalizedHFEndpoint, "https://hf-mirror.com")
        XCTAssertEqual(defaults.string(forKey: "hfEndpoint"), "https://hf-mirror.com/")
    }

    func testNormalizedHFEndpointRejectsInvalidValues() {
        var config = AppSettings(defaults: isolatedDefaults()).configuration

        config.hfEndpoint = "   "
        XCTAssertNil(config.normalizedHFEndpoint)

        config.hfEndpoint = "hf-mirror.com"
        XCTAssertNil(config.normalizedHFEndpoint, "缺少 scheme 应视为无效")

        config.hfEndpoint = "ftp://hf-mirror.com"
        XCTAssertNil(config.normalizedHFEndpoint)

        config.hfEndpoint = "https://hf-mirror.com///"
        XCTAssertEqual(config.normalizedHFEndpoint, "https://hf-mirror.com")
    }

    func testNormalizedHFEndpointRejectsRemoteClearTextMirrors() {
        var config = AppSettings(defaults: isolatedDefaults()).configuration

        // Weights from a mirror are loaded into the process, so a transfer that can
        // be tampered with decides what the app runs.
        config.hfEndpoint = "http://hf-mirror.com"
        XCTAssertNil(config.normalizedHFEndpoint)

        // A local mirror over plain HTTP stays usable.
        config.hfEndpoint = "http://127.0.0.1:8080"
        XCTAssertEqual(config.normalizedHFEndpoint, "http://127.0.0.1:8080")
        config.hfEndpoint = "http://localhost:8080/"
        XCTAssertEqual(config.normalizedHFEndpoint, "http://localhost:8080")
    }

    func testRejectedHFMirrorIsReportedToTheUI() {
        let settings = AppSettings(defaults: isolatedDefaults())

        XCTAssertFalse(settings.hfEndpointRejected, "an empty field is not a rejection")

        settings.hfEndpoint = "https://hf-mirror.com"
        XCTAssertFalse(settings.hfEndpointRejected)

        settings.hfEndpoint = "http://hf-mirror.com"
        XCTAssertTrue(settings.hfEndpointRejected)
    }

    func testWhisperKitModelMigrationDropsRepoPrefix() {
        let defaults = isolatedDefaults()
        defaults.set("openai_whisper-large-v3-v20240930_626MB", forKey: "whisperKitModel")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.whisperKitModel, "large-v3-v20240930_626MB")
        XCTAssertEqual(defaults.string(forKey: "whisperKitModel"), "large-v3-v20240930_626MB")
    }

    func testRoleCandidatesAreLimitedToThreeAndClearingSelectionUnlocksRole() {
        let settings = AppSettings(defaults: isolatedDefaults())
        let first = RoleProfile.softwareEngineer
        let second = RoleProfile.foreignTrade
        settings.setRoleSelected(first, selected: true)
        settings.setRoleSelected(second, selected: true)
        settings.lockRole(first)

        XCTAssertEqual(settings.activeRoleCandidates.map(\.id), [first.id, second.id])
        XCTAssertEqual(settings.lockedRole?.id, first.id)

        settings.setRoleSelected(first, selected: false)
        XCTAssertNil(settings.lockedRole)
        XCTAssertEqual(settings.candidateRoleIDs, [second.id])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "VibeVoiceOSS.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Do not let a developer machine's shared Keychain model migrate this isolated suite into API mode.
        defaults.set(LanguageModelBackend.disabled.rawValue, forKey: "llmBackend")
        return defaults
    }
}
