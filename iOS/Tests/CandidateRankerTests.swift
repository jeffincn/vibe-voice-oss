import XCTest
@testable import VibeVoiceMobile

final class CandidateRankerTests: XCTestCase {
    func testRestrictedFallbackDoesNotPersistAcceptanceCounts() async {
        let ranker = PassthroughCandidateRanker(persistLearning: false)
        let candidates = [
            RimeCandidate(text: "你好", comment: nil),
            RimeCandidate(text: "拟好", comment: nil)
        ]
        let context = PredictionContext(preedit: "nihao", candidates: candidates)
        ranker.record(candidates[1], context: context)
        let ranked = await ranker.rank(context)
        XCTAssertEqual(ranked.map(\.text), ["你好", "拟好"])
    }

    func testPrivacyStateDowngradesWithoutFullAccessOrForSecureFields() {
        let restricted = KeyboardPrivacyState(hasFullAccess: false, isSecureTextEntry: false)
        XCTAssertEqual(restricted.status, .restrictedAccess)
        XCTAssertFalse(restricted.allowsDocumentContext)
        XCTAssertFalse(restricted.allowsPersistentLearning)
        XCTAssertFalse(restricted.allowsEnhancedInference)

        let secure = KeyboardPrivacyState(hasFullAccess: true, isSecureTextEntry: true)
        XCTAssertEqual(secure.status, .secureField)
        XCTAssertFalse(secure.allowsDocumentContext)
        XCTAssertFalse(secure.allowsPersistentLearning)
        XCTAssertFalse(secure.allowsEnhancedInference)
    }

    func testFallbackPreservesAllRimeCandidatesAndUsesLocalAcceptanceCounts() async {
        let ranker = PassthroughCandidateRanker()
        let candidates = [
            RimeCandidate(text: "你好", comment: nil),
            RimeCandidate(text: "拟好", comment: nil),
        ]
        let context = PredictionContext(preedit: "nihao", candidates: candidates)
        _ = await ranker.rank(context)
        ranker.record(candidates[1], context: context)
        let ranked = await ranker.rank(context)
        XCTAssertEqual(ranked.first?.text, "拟好")
        XCTAssertEqual(Set(ranked.map(\.text)), Set(["你好", "拟好"]))
    }

    func testCoreMLRankerFallsBackWhenModelIsMissing() async {
        let ranker = CoreMLCandidateRanker(modelURL: nil)
        XCTAssertEqual(ranker.status, .unavailable("No candidate ranker model installed"))
        let result = await ranker.rank(PredictionContext(
            preedit: "hao",
            candidates: [RimeCandidate(text: "好", comment: nil)]
        ))
        XCTAssertEqual(result.map(\.text), ["好"])
    }

    func testBuiltinCoreMLModelIsDiscoverable() {
        guard let url = CandidateRankerFactory.modelURL() else {
            XCTFail("The built-in VibeCandidateRanker.mlmodelc was not bundled")
            return
        }
        let ranker = CoreMLCandidateRanker(modelURL: url)
        if case .ready = ranker.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Built-in model did not load: \(ranker.status)")
        }
    }

    func testBuiltinCoreMLModelRunsInference() async {
        guard let url = CandidateRankerFactory.modelURL() else {
            XCTFail("Built-in model missing")
            return
        }
        let ranker = CoreMLCandidateRanker(modelURL: url)
        let candidates = [
            RimeCandidate(text: "我到了方案的现场", comment: nil, rawWeight: 100),
            RimeCandidate(text: "我倒了方案的现场", comment: nil, rawWeight: 10),
        ]
        _ = await ranker.rank(PredictionContext(preedit: "wodaolefangandexianchang", candidates: candidates))
        XCTAssertTrue(ranker.lastInferenceUsed)
    }

    func testCoreMLUsesWholeSentenceContextToResolveHomophone() async {
        guard let url = CandidateRankerFactory.modelURL() else {
            XCTFail("Built-in model missing")
            return
        }
        let ranker = CoreMLCandidateRanker(modelURL: url)
        let candidates = [
            RimeCandidate(text: "我倒了方案的现场", comment: nil, rawWeight: 100_000),
            RimeCandidate(text: "我到了方案的现场", comment: nil, rawWeight: 0)
        ]
        let context = PredictionContext(preedit: "wodaolefangandexianchang", candidates: candidates)
        let ranked = await ranker.rank(context)
        XCTAssertTrue(ranker.lastInferenceUsed)
        XCTAssertEqual(ranked.first?.text, "我到了方案的现场")
    }

    func testCoreMLUsesDocumentDialogueContext() async {
        guard let url = CandidateRankerFactory.modelURL() else {
            XCTFail("Built-in model missing")
            return
        }
        let ranker = CoreMLCandidateRanker(modelURL: url)
        let candidates = [
            RimeCandidate(text: "号", comment: nil, rawWeight: 100_000),
            RimeCandidate(text: "好", comment: nil, rawWeight: 0)
        ]
        let context = PredictionContext(preedit: "hao", documentContext: "这个方案很",
                                         candidates: candidates)
        let ranked = await ranker.rank(context)
        XCTAssertTrue(ranker.lastInferenceUsed)
        XCTAssertEqual(ranked.first?.text, "好")
    }
}
