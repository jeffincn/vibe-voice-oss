import XCTest
@testable import VibeVoiceMobile

final class MobileL10nTests: XCTestCase {
    override func tearDown() {
        MobileL10n.language = .resolveFromSystem()
        super.tearDown()
    }

    /// A missing entry falls back to the other catalog rather than crashing, so
    /// only a test like this one can catch a key that was never translated.
    func testEveryKeyIsTranslatedInEveryLanguage() {
        for key in MobileL10n.Key.allCases {
            for language in MobileUILanguage.allCases {
                XCTAssertTrue(
                    MobileL10n.hasTranslation(key, language: language),
                    "Missing \(language.rawValue) translation for \(key.rawValue)"
                )
            }
        }
    }

    func testChineseAndEnglishActuallyDiffer() {
        XCTAssertNotEqual(
            MobileL10n.string(.homeStartRecording, language: .zhHans),
            MobileL10n.string(.homeStartRecording, language: .english)
        )
        XCTAssertEqual(MobileL10n.string(.homeBridgeReset, language: .english), "Reset")
        XCTAssertEqual(MobileL10n.string(.homeBridgeReset, language: .zhHans), "重置")
    }

    func testSystemLanguageResolution() {
        XCTAssertEqual(MobileUILanguage.resolve(id: "zh-Hans-CN"), .zhHans)
        XCTAssertEqual(MobileUILanguage.resolve(id: "zh-Hant-TW"), .zhHans)
        XCTAssertEqual(MobileUILanguage.resolve(id: "ZH"), .zhHans)
        XCTAssertEqual(MobileUILanguage.resolve(id: "en-GB"), .english)
        // Anything the catalog does not cover reads better in English than in a
        // language the user did not ask for.
        XCTAssertEqual(MobileUILanguage.resolve(id: "ja"), .english)
        XCTAssertEqual(MobileUILanguage.resolveFromSystem(preferred: []), .english)
        XCTAssertEqual(MobileUILanguage.resolveFromSystem(preferred: ["zh-Hans"]), .zhHans)
    }

    func testFormattedKeysSubstituteInOrder() {
        MobileL10n.language = .english
        XCTAssertEqual(MobileL10n.t(.candidateAccessibility, 2, "hello"), "Candidate 2: hello")
        XCTAssertEqual(MobileL10n.t(.phaseFailed, "no network"), "Failed: no network")
        MobileL10n.language = .zhHans
        XCTAssertEqual(MobileL10n.t(.candidateAccessibility, 2, "你好"), "候选 2：你好")
    }

    /// The status raw values are the on-disk representation shared by two
    /// processes; only the display name is allowed to change with the language.
    func testBridgeStatusRawValuesStayStable() {
        XCTAssertEqual(VoiceBridgeStatus.recording.rawValue, "recording")
        XCTAssertEqual(VoiceBridgeStatus.consumed.rawValue, "consumed")
        MobileL10n.language = .english
        XCTAssertEqual(VoiceBridgeStatus.recording.displayName, "Recording")
        MobileL10n.language = .zhHans
        XCTAssertEqual(VoiceBridgeStatus.recording.displayName, "正在录音")
    }

    func testOutputModeLabelsFollowTheLanguage() {
        MobileL10n.language = .english
        XCTAssertEqual(VoiceOutputMode.translate.label, "Translate")
        XCTAssertEqual(KeyboardLanguage.english.toggleLabel, "EN")
        MobileL10n.language = .zhHans
        XCTAssertEqual(VoiceOutputMode.translate.label, "翻译")
    }
}
