import XCTest
@testable import VibeVoiceOSS

final class L10nTests: XCTestCase {
    func testJapaneseCatalogHasEveryUIKey() {
        for key in L10n.Key.allCases {
            XCTAssertTrue(
                L10n.hasTranslation(key, language: .japanese),
                "Missing Japanese translation for \(key.rawValue)"
            )
        }
    }

    func testJapaneseInterfaceIsDistinctFromEnglishAndChinese() {
        defer { L10n.language = .zhHans }
        XCTAssertEqual(AppUILanguage.resolve(id: "ja"), .japanese)
        XCTAssertEqual(AppUILanguage.japanese.displayName, "日本語")
        XCTAssertTrue(L10n.string(.startRecording, language: .japanese).contains("録音"))
        XCTAssertNotEqual(
            L10n.string(.startRecording, language: .japanese),
            L10n.string(.startRecording, language: .english)
        )
        XCTAssertNotEqual(
            L10n.string(.startRecording, language: .japanese),
            L10n.string(.startRecording, language: .zhHans)
        )
    }
}
