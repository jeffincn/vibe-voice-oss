import Foundation
import Testing
@testable import VibeVoicePinyin

struct ReasoningRimeReconcilerTests {
    @Test func prefersRimePeerDifferingOnlyInLastCharacter() {
        let rime = [
            RimeCandidate(text: "魔法", comment: nil, engineIndex: 0, rawWeight: 100, source: nil),
            RimeCandidate(text: "魔法棒", comment: nil, engineIndex: 1, rawWeight: 90, source: nil),
            RimeCandidate(text: "摸", comment: nil, engineIndex: 2, rawWeight: 80, source: nil),
        ]
        let outcome = ReasoningRimeReconciler.reconcile(composed: "魔法帮", rimeCandidates: rime)
        #expect(outcome.text == "魔法棒")
        #expect(outcome.usedRimePeer)
    }

    @Test func keepsCompositionWhenNoBetterPeer() {
        let rime = [
            RimeCandidate(text: "我想", comment: nil, engineIndex: 0, rawWeight: 100, source: nil),
        ]
        let outcome = ReasoningRimeReconciler.reconcile(composed: "我想用", rimeCandidates: rime)
        #expect(outcome.text == "我想用")
        #expect(!outcome.usedRimePeer)
    }
}

struct MagicWandPhraseTests {
    private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private static let lexicon: PinyinLexicon = {
        let lex = PinyinLexicon()
        lex.loadSynchronously(
            from: repoRoot.appendingPathComponent("Resources/InputMethod/RimeData/pinyin_simp.dict.yaml"),
            phraseOverlayURL: repoRoot.appendingPathComponent("Resources/InputMethod/Lexicon/common-phrases.tsv"),
            includeSharedCorrections: false
        )
        return lex
    }()

    @Test func mofabangComposesToMagicWand() {
        #expect(Self.lexicon.isReady)
        let result = PhraseComposer.compose(
            rawInput: "mofabang",
            lexicon: Self.lexicon,
            fuzzyEnabled: false
        )
        #expect(result?.text == "魔法棒")
    }
}
