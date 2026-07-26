import XCTest
@testable import VibeVoiceMobile

final class RimeEngineTests: XCTestCase {
    func testFallbackFullPinyinProducesCandidateAndCommits() {
        let engine = PrototypeRimeEngine()
        "nihao".forEach { engine.process(character: $0) }

        XCTAssertFalse(engine.process(character: "1").handled)

        XCTAssertEqual(engine.snapshot.preedit, "nihao")
        XCTAssertEqual(engine.snapshot.candidates.first?.text, "你好")
        XCTAssertEqual(engine.commitBestCandidate(), "你好")
        XCTAssertEqual(engine.snapshot, .empty)
    }

    func testFallbackBackspaceEditsCompositionBeforeHostText() {
        let engine = PrototypeRimeEngine()
        "ni".forEach { engine.process(character: $0) }

        engine.backspace()

        XCTAssertEqual(engine.snapshot.preedit, "n")
    }

    func testLibrimeFullPinyinProducesChineseCandidateAndCommits() throws {
        let userDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceRimeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: userDirectory) }

        let engine = try RimeEngineFactory.make(
            bundle: .main,
            userDataDirectory: userDirectory,
            performMaintenance: true,
            fullCheck: true
        )
        "nihao".forEach { engine.process(character: $0) }

        XCTAssertEqual(engine.snapshot.preedit.replacingOccurrences(of: " ", with: ""), "nihao")
        XCTAssertTrue(
            engine.snapshot.candidates.contains { $0.text == "你好" },
            "Expected 你好 in \(engine.snapshot.candidates)"
        )
        let committed = engine.commitBestCandidate()
        XCTAssertNotNil(committed)
        XCTAssertTrue(committed?.contains(where: { $0.isASCII == false }) == true)
        XCTAssertEqual(engine.snapshot.preedit, "")
    }
}
