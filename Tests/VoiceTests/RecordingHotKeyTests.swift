import Carbon.HIToolbox
import XCTest
@testable import VibeVoiceOSS

final class RecordingHotKeyTests: XCTestCase {
    func testModeChordsAreCommandShift() {
        for mode in RecordingOutputMode.allCases {
            XCTAssertEqual(mode.carbonModifiers, UInt32(cmdKey | shiftKey))
            XCTAssertFalse(mode.chordLabel.isEmpty)
        }
        XCTAssertEqual(RecordingOutputMode.conversation.chordLabel, "⌘⇧R")
        XCTAssertEqual(RecordingOutputMode.english.chordLabel, "⌘⇧E")
        XCTAssertEqual(RecordingOutputMode.structured.chordLabel, "⌘⇧F")
        XCTAssertEqual(RecordingOutputMode.prompt.chordLabel, "⌘⇧T")
    }

    func testCarbonHotKeyIDsAreUnique() {
        let ids = RecordingOutputMode.allCases.map(\.carbonHotKeyID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(RecordingOutputMode.resolve(carbonHotKeyID: 1), .conversation)
        XCTAssertEqual(RecordingOutputMode.resolve(carbonHotKeyID: 2), .structured)
        XCTAssertEqual(RecordingOutputMode.resolve(carbonHotKeyID: 3), .prompt)
        XCTAssertEqual(RecordingOutputMode.resolve(carbonHotKeyID: 4), .english)
        XCTAssertNil(RecordingOutputMode.resolve(carbonHotKeyID: 99))
    }

    func testLegacyResolveFallsBackToConversation() {
        let chord = RecordingHotKey.resolve(id: "not-a-real-hotkey")
        XCTAssertEqual(chord.id, RecordingOutputMode.conversation.rawValue)
    }

    func testShortcutLegendMentionsAllModes() {
        let legend = RecordingOutputMode.shortcutLegend
        XCTAssertTrue(legend.contains("⌘⇧R"))
        XCTAssertTrue(legend.contains("⌘⇧F"))
        XCTAssertTrue(legend.contains("⌘⇧T"))
    }
}
