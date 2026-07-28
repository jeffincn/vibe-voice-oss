import Foundation
import Testing
@testable import VibeVoiceInputShared

struct CandidateRankerTests {
    /// The repo copy, because in a test process `Bundle.main` is xctest rather
    /// than the input method bundle the runtime looks in.
    private static var bundledModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/CandidateRanker/VibeCandidateRanker.mlmodelc", isDirectory: true)
    }

    private static func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "vibevoice.tests.\(UUID().uuidString)")!
    }

    private static let nihao = [
        RimeCandidate(text: "你好", engineIndex: 0),
        RimeCandidate(text: "拟好", engineIndex: 1),
    ]

    @Test func restrictedFallbackDoesNotPersistAcceptanceCounts() {
        let ranker = PassthroughCandidateRanker(persistLearning: false, defaults: Self.isolatedDefaults())
        let context = PredictionContext(preedit: "nihao", candidates: Self.nihao)
        ranker.record(Self.nihao[1], context: context)
        #expect(ranker.rank(context).map(\.text) == ["你好", "拟好"])
    }

    @Test func fallbackPreservesRimeOrderUntilTheUserAcceptsSomethingElse() {
        let ranker = PassthroughCandidateRanker(defaults: Self.isolatedDefaults())
        let context = PredictionContext(preedit: "nihao", candidates: Self.nihao)
        #expect(ranker.rank(context).map(\.text) == ["你好", "拟好"])
        ranker.record(Self.nihao[1], context: context)
        let ranked = ranker.rank(context)
        #expect(ranked.first?.text == "拟好")
        #expect(Set(ranked.map(\.text)) == Set(["你好", "拟好"]))
    }

    /// Swift's sort is not stable, so an unlearned page has to be pinned to the
    /// engine's order explicitly rather than by luck.
    @Test func fallbackKeepsUnlearnedCandidatesInEngineOrder() {
        let ranker = PassthroughCandidateRanker(defaults: Self.isolatedDefaults())
        let candidates = (0..<32).map { RimeCandidate(text: "候选\($0)", engineIndex: $0) }
        let ranked = ranker.rank(PredictionContext(preedit: "houxuan", candidates: candidates))
        #expect(ranked.map(\.engineIndex) == Array(0..<32))
    }

    @Test func coreMLRankerFallsBackWhenModelIsMissing() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: nil
        )
        #expect(ranker.status == .unavailable("No candidate ranker model installed"))
        #expect(ranker.rank(PredictionContext(preedit: "nihao", candidates: Self.nihao)).map(\.text)
            == ["你好", "拟好"])
    }

    @Test func bundledModelLoadsAndRunsInference() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL
        )
        guard case .ready = ranker.status else {
            Issue.record("Bundled model did not load: \(ranker.status)")
            return
        }
        _ = ranker.rank(PredictionContext(
            preedit: "wodaolefangandexianchang",
            candidates: [
                RimeCandidate(text: "我倒了方案的现场", engineIndex: 0),
                RimeCandidate(text: "我到了方案的现场", engineIndex: 1),
            ]
        ))
        #expect(ranker.lastInferenceUsed)
    }

    @Test func trainedHomophoneIsPromotedAheadOfTheEngineOrder() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL
        )
        let ranked = ranker.rank(PredictionContext(
            preedit: "wodaolefangandexianchang",
            candidates: [
                RimeCandidate(text: "我倒了方案的现场", engineIndex: 0),
                RimeCandidate(text: "我到了方案的现场", engineIndex: 1),
            ]
        ))
        #expect(ranker.lastInferenceUsed)
        #expect(ranked.first?.text == "我到了方案的现场")
    }

    @Test func documentContextResolvesAHomophone() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL
        )
        let ranked = ranker.rank(PredictionContext(
            preedit: "hao",
            documentContext: "这个方案很",
            candidates: [
                RimeCandidate(text: "号", engineIndex: 0),
                RimeCandidate(text: "好", engineIndex: 1),
            ]
        ))
        #expect(ranker.lastInferenceUsed)
        #expect(ranked.first?.text == "好")
    }

    @Test func dialogueContextPromotesHomophoneOverEngineOrder() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL
        )
        let ranked = ranker.rank(PredictionContext(
            preedit: "chucha",
            documentContext: "你们公司昨天不是刚公布了办公室禁止",
            candidates: [
                RimeCandidate(text: "出岔", engineIndex: 0),
                RimeCandidate(text: "出差", engineIndex: 1),
            ]
        ))
        #expect(ranker.lastInferenceUsed)
        #expect(ranked.first?.text == "出差")
    }

    @Test func committedPrefixIsExtractedFromPartialPreedit() {
        #expect(PredictionContext.committedPrefix(fromPreedit: "真实nei rong") == "真实")
        #expect(PredictionContext.committedPrefix(fromPreedit: "neirong") == "")
        #expect(PredictionContext.committedPrefix(fromPreedit: "方案hao") == "方案")
    }

    @Test func mergeContextPrefersDocumentAndFallsBackToSession() {
        #expect(PredictionContext.mergeContext(preceding: "", session: "会话前文") == "会话前文")
        #expect(PredictionContext.mergeContext(preceding: "文档前文", session: "") == "文档前文")
        let merged = PredictionContext.mergeContext(preceding: "后半句", session: "前半句")
        #expect(merged.contains("前半句"))
        #expect(merged.contains("后半句"))
    }

    /// The scorer is trained on a small seed corpus, so it is allowed to adjust
    /// the engine's order, never to replace it. Anything further down the page
    /// than the shift budget has to stay put.
    @Test func rerankingCannotMoveACandidateBeyondTheShiftBudget() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL,
            maxRankShift: 2
        )
        let candidates = (0..<9).map { RimeCandidate(text: "词\($0)", engineIndex: $0) }
        let ranked = ranker.rank(PredictionContext(preedit: "ci", candidates: candidates))
        #expect(ranker.lastInferenceUsed)
        for (position, candidate) in ranked.enumerated() {
            #expect(abs(position - candidate.engineIndex) <= 2)
        }
    }

    @Test func rerankingNeverDropsOrDuplicatesCandidates() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL
        )
        let candidates = (0..<9).map { RimeCandidate(text: "词\($0)", engineIndex: $0) }
        let ranked = ranker.rank(PredictionContext(preedit: "ci", candidates: candidates))
        #expect(ranked.count == candidates.count)
        #expect(Set(ranked.map(\.engineIndex)) == Set(candidates.map(\.engineIndex)))
    }

    /// A single candidate cannot be reordered, so the model must not be paid
    /// for on the most common page shape.
    @Test func singleCandidateSkipsInference() {
        let ranker = CoreMLCandidateRanker(
            fallback: PassthroughCandidateRanker(defaults: Self.isolatedDefaults()),
            modelURL: Self.bundledModelURL
        )
        let ranked = ranker.rank(PredictionContext(
            preedit: "hao",
            candidates: [RimeCandidate(text: "好", engineIndex: 0)]
        ))
        #expect(ranked.map(\.text) == ["好"])
        #expect(ranker.lastInferenceUsed == false)
    }

    @Test func contextWindowIsBounded() {
        let context = PredictionContext(
            preedit: "hao",
            documentContext: String(repeating: "字", count: 800),
            candidates: Self.nihao
        )
        #expect(context.documentContext.count == PredictionContext.contextCharacterLimit)
    }

    @Test func featureVectorMatchesModelWidth() {
        let values = CoreMLCandidateRanker.sentenceFeatures(
            candidate: RimeCandidate(text: "出差", engineIndex: 0),
            context: PredictionContext(
                preedit: "chucha",
                committedPrefix: "",
                documentContext: "办公室禁止",
                candidates: []
            )
        )
        #expect(values.count == CoreMLCandidateRanker.featureCount)
    }
}
