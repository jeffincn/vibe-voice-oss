import XCTest
@testable import VibeVoiceOSS

final class TargetLanguageTests: XCTestCase {
    func testSimplifiedChineseExpectsCJK() {
        let language = TargetLanguage.resolve(id: "zh-Hans")
        XCTAssertTrue(language.translates)
        XCTAssertTrue(language.expectsCJK)
        XCTAssertTrue(language.outputLooksCompatible("如果内容是实时输出的，我怎么知道信息是否完整？"))
        XCTAssertFalse(language.outputLooksCompatible(
            "If the content we are outputting is in real-time, how can I know that the information is complete?"
        ))
    }

    func testEnglishDoesNotRequireCJK() {
        let language = TargetLanguage.resolve(id: "en")
        XCTAssertTrue(language.translates)
        XCTAssertFalse(language.expectsCJK)
        XCTAssertTrue(language.outputLooksCompatible("Hello world from translation"))
    }

    func testNoneDoesNotTranslate() {
        XCTAssertFalse(TargetLanguage.none.translates)
    }

    func testNewLanguageOptionsAreAvailable() {
        let expected = ["zh-Hant-TW", "ja", "ko", "fr", "es", "hi", "th", "it", "el", "he", "ar", "vi"]
        for id in expected {
            let language = TargetLanguage.resolve(id: id)
            XCTAssertTrue(language.translates, "\(id) should be a translation target")
        }
    }

    func testJapaneseUsesNaturalLanguageHintAndModelFloor() {
        let language = TargetLanguage.resolve(id: "ja")
        XCTAssertEqual(language.minimumModelVersion, 5.6)
        XCTAssertTrue(language.styleHint.contains("native Japanese editor"))
        XCTAssertTrue(TranslationClient.supportsJapaneseNaturalTranslation(model: "gpt-5.6"))
        XCTAssertTrue(TranslationClient.supportsJapaneseNaturalTranslation(model: "model-v6"))
        XCTAssertFalse(TranslationClient.supportsJapaneseNaturalTranslation(model: "gpt-5.5"))
        XCTAssertFalse(TranslationClient.supportsJapaneseNaturalTranslation(model: "Qwen3.5-35B"))
    }

    func testTaiwaneseHokkienIsRetired() {
        XCTAssertFalse(TargetLanguage.resolve(id: "nan-TW").translates)
        XCTAssertFalse(TargetLanguage.translationOptions.contains { $0.id == "nan-TW" })
    }

    func testKoreanHindiAndThaiValidateTheirNativeScripts() {
        XCTAssertTrue(TargetLanguage.resolve(id: "ko").outputLooksCompatible("내일 오전에 영화를 볼 거예요."))
        XCTAssertFalse(TargetLanguage.resolve(id: "ko").outputLooksCompatible("I will watch a movie tomorrow morning."))
        XCTAssertTrue(TargetLanguage.resolve(id: "hi").outputLooksCompatible("मैं कल सुबह फिल्म देखने जाऊंगा।"))
        XCTAssertTrue(TargetLanguage.resolve(id: "th").outputLooksCompatible("ฉันจะไปดูหนังพรุ่งนี้เช้า"))
        XCTAssertTrue(TargetLanguage.resolve(id: "el").outputLooksCompatible("Θα πάω να δω μια ταινία αύριο το πρωί."))
        XCTAssertFalse(TargetLanguage.resolve(id: "el").outputLooksCompatible("I will watch a movie tomorrow morning."))
        XCTAssertTrue(TargetLanguage.resolve(id: "he").outputLooksCompatible("אני אלך לראות סרט מחר בבוקר."))
        XCTAssertFalse(TargetLanguage.resolve(id: "he").outputLooksCompatible("I will watch a movie tomorrow morning."))
        XCTAssertTrue(TargetLanguage.resolve(id: "ar").outputLooksCompatible("سأذهب لمشاهدة فيلم غدًا صباحًا."))
        XCTAssertFalse(TargetLanguage.resolve(id: "ar").outputLooksCompatible("I will watch a movie tomorrow morning."))
    }
}
