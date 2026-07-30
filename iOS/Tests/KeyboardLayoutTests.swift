import XCTest
@testable import VibeVoiceMobile

final class KeyboardLayoutTests: XCTestCase {
    private let planes: [KeyboardPlane] = [.letters, .numbers, .symbols]

    func testEveryPlaneHasThreeCharacterRows() {
        for plane in planes {
            XCTAssertEqual(plane.rows.count, 3, "\(plane) should have three rows")
        }
    }

    func testEveryPlaneEndsItsLastRowWithBackspace() {
        for plane in planes {
            XCTAssertEqual(plane.rows[2].last, .backspace, "\(plane) is missing backspace")
        }
    }

    /// A typo in a layout string would otherwise only show up as a key that
    /// types two characters at once.
    func testCharacterKeysCarryExactlyOneCharacter() {
        for plane in planes {
            for key in plane.rows.flatMap({ $0 }) {
                guard case let .character(text) = key else { continue }
                XCTAssertEqual(text.count, 1, "\(text) is not a single character")
            }
        }
    }

    func testNoCharacterIsReachableTwiceWithinAPlane() {
        for plane in planes {
            let characters = plane.rows.flatMap { $0 }.compactMap { key -> String? in
                guard case let .character(text) = key else { return nil }
                return text
            }
            XCTAssertEqual(
                characters.count,
                Set(characters).count,
                "\(plane) repeats a character"
            )
        }
    }

    func testLettersPlaneCoversTheAlphabet() {
        let letters = KeyboardPlane.letters.rows.flatMap { $0 }.compactMap { key -> String? in
            guard case let .character(text) = key else { return nil }
            return text
        }
        XCTAssertEqual(Set(letters), Set("abcdefghijklmnopqrstuvwxyz".map(String.init)))
    }

    func testOnlyTheMiddleLetterRowIsInset() {
        XCTAssertFalse(KeyboardPlane.letters.isInset(row: 0))
        XCTAssertTrue(KeyboardPlane.letters.isInset(row: 1))
        XCTAssertFalse(KeyboardPlane.letters.isInset(row: 2))
        XCTAssertFalse(KeyboardPlane.numbers.isInset(row: 1))
    }

    func testShiftAndSymbolKeysAreReachable() {
        XCTAssertTrue(KeyboardPlane.letters.rows[2].contains(.shift))
        XCTAssertTrue(KeyboardPlane.numbers.rows[2].contains(.plane(.symbols)))
        XCTAssertTrue(KeyboardPlane.symbols.rows[2].contains(.plane(.numbers)))
    }

    func testAlternatePlaneRoundTrips() {
        XCTAssertEqual(KeyboardPlane.letters.alternate, .numbers)
        XCTAssertEqual(KeyboardPlane.numbers.alternate, .letters)
        XCTAssertEqual(KeyboardPlane.symbols.alternate, .letters)
        XCTAssertEqual(KeyboardPlane.letters.alternateLabel, "123")
        XCTAssertEqual(KeyboardPlane.numbers.alternateLabel, "ABC")
    }

    func testShiftRaisesOnlyWhenNotOff() {
        XCTAssertFalse(KeyboardShift.off.isRaised)
        XCTAssertTrue(KeyboardShift.on.isRaised)
        XCTAssertTrue(KeyboardShift.locked.isRaised)
    }

    func testChinesePunctuationMapsCommonMarks() {
        XCTAssertEqual(ChinesePunctuation.mapped(","), "，")
        XCTAssertEqual(ChinesePunctuation.mapped("."), "。")
        XCTAssertEqual(ChinesePunctuation.mapped("?"), "？")
        XCTAssertEqual(ChinesePunctuation.mapped("!"), "！")
        XCTAssertEqual(ChinesePunctuation.mapped(":"), "：")
        XCTAssertEqual(ChinesePunctuation.mapped(";"), "；")
        XCTAssertEqual(ChinesePunctuation.mapped("("), "（")
        XCTAssertEqual(ChinesePunctuation.mapped(")"), "）")
        XCTAssertEqual(ChinesePunctuation.mapped("-"), "-")
        XCTAssertEqual(ChinesePunctuation.mapped("1"), "1")
    }
}
