import XCTest
@testable import VibeVoice

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
}
