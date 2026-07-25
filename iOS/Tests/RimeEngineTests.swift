import XCTest
@testable import VibeVoiceMobile

final class RimeEngineTests: XCTestCase {
    func testFullPinyinProducesCandidateAndCommits() {
        let engine = PrototypeRimeEngine()
        "nihao".forEach { engine.process(letter: $0) }

        XCTAssertEqual(engine.snapshot.preedit, "nihao")
        XCTAssertEqual(engine.snapshot.candidates.first?.text, "你好")
        XCTAssertEqual(engine.commitBestCandidate(), "你好")
        XCTAssertEqual(engine.snapshot, .empty)
    }

    func testBackspaceEditsCompositionBeforeHostText() {
        let engine = PrototypeRimeEngine()
        "ni".forEach { engine.process(letter: $0) }

        engine.backspace()

        XCTAssertEqual(engine.snapshot.preedit, "n")
    }
}
