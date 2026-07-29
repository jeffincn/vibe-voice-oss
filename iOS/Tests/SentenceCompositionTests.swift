import XCTest
@testable import VibeVoiceMobile

final class SentenceCompositionTests: XCTestCase {
    func testContinuousPinyinProducesSentenceCandidates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sentence-composition-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = try RimeEngineFactory.make(
            bundle: .main,
            userDataDirectory: directory,
            performMaintenance: true,
            fullCheck: true
        )
        for syllable in "wo dao le fang an de xian chang".split(separator: " ") {
            for character in syllable { _ = engine.process(character: character) }
            // KeyboardViewController now intentionally does not send this
            // separator to librime while Chinese composition is active.
        }
        XCTAssertTrue(engine.snapshot.isComposing)
        XCTAssertTrue(engine.snapshot.candidates.contains { $0.text.contains("现场") })
        XCTAssertEqual(engine.commitBestCandidate(), "我到了方案的现场")
    }

    func testLongSentenceProbesKeepWholeComposition() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("long-sentence-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = try RimeEngineFactory.make(
            bundle: .main,
            userDataDirectory: directory,
            performMaintenance: true,
            fullCheck: true
        )
        let probes: [(String, String?)] = [
            ("wodaolefangandexianchang", "我到了方案的现场"),
            ("womenbixuanbujiubandewanchengxitongbushu", "我们必须按部就班的完成系统部署"),
            ("mianduitufaguzhangjishutuanduiyishiyichoumozhan", nil),
        ]
        for (pinyin, expected) in probes {
            for character in pinyin { _ = engine.process(character: character) }
            let result = engine.commitBestCandidate() ?? ""
            print("SENTENCE_PROBE|\(pinyin)|\(result)")
            if let expected { XCTAssertEqual(result, expected) }
            engine.reset()
        }
    }

    func testUserProvidedPinyinWithAndWithoutCoreML() async throws {
        let probes = [
            ("wodao le fangan de xianchang", "我到了方案的现场"),
            ("wo men bi xu an bu jiu ban de wan cheng xi tong bu shu", "我们必须按部就班的完成系统部署"),
            ("mian dui tu fa gu zhang ji shu tuan dui yi shi yi chou mo zhan", "面对突发故障技术团队一时一筹莫展")
        ]
        for (spaced, expected) in probes {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("sentence-user-(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let engine = try RimeEngineFactory.make(bundle: .main, userDataDirectory: directory,
                                                     performMaintenance: true, fullCheck: true)
            for character in spaced.replacingOccurrences(of: " ", with: "") { _ = engine.process(character: character) }
            let candidates = engine.snapshot.candidates
            let context = PredictionContext(preedit: engine.snapshot.preedit, candidates: candidates)
            let baseline = PassthroughCandidateRanker()
            let enhanced = CoreMLCandidateRanker(modelURL: CandidateRankerFactory.modelURL())
            let baselineTop = await baseline.rank(context).first?.text ?? ""
            let enhancedTop = await enhanced.rank(context).first?.text ?? ""
            let committed = engine.commitBestCandidate() ?? ""
            print("USER_SENTENCE_PROBE|\(spaced)|baseline=\(baselineTop)|coreml=\(enhancedTop)|commit=\(committed)|expected=\(expected)")
            XCTAssertEqual(committed, expected)
        }
    }
}
