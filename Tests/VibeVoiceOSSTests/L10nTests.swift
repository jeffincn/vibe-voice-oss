import XCTest
@testable import VibeVoiceOSS

final class L10nTests: XCTestCase {
    func testEveryCatalogHasEveryUIKey() {
        for language in AppUILanguage.allCases {
            for key in L10n.Key.allCases {
                XCTAssertTrue(
                    L10n.hasTranslation(key, language: language),
                    "Missing \(language.rawValue) translation for \(key.rawValue)"
                )
            }
        }
    }

    /// `L10n.t(key, args)` feeds the looked-up string to `String(format:)`. A translation
    /// that drops a `%@` or turns it into `%d` reads the argument list wrong at runtime,
    /// which is a crash rather than a cosmetic bug, and only in that one language.
    func testFormatSpecifiersAgreeAcrossLanguages() throws {
        let specifier = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfsu]")
        for key in L10n.Key.allCases {
            let shapes = AppUILanguage.allCases.map { language -> [String] in
                let value = L10n.string(key, language: language)
                let range = NSRange(value.startIndex..., in: value)
                return specifier.matches(in: value, range: range).map {
                    String(value[Range($0.range, in: value)!])
                }
            }
            XCTAssertEqual(
                Set(shapes.map { $0.joined(separator: ",") }).count, 1,
                "Format specifiers differ across languages for \(key.rawValue): \(shapes)"
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
