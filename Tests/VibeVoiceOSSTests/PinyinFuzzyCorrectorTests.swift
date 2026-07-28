import Foundation
import Testing
@testable import VibeVoiceInputShared

struct PinyinFuzzyCorrectorTests {
    private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private static let lexicon: PinyinLexicon = {
        let lex = PinyinLexicon()
        lex.loadSynchronously(
            from: repoRoot.appendingPathComponent("Resources/RimeData/pinyin_simp.dict.yaml"),
            phraseOverlayURL: repoRoot.appendingPathComponent("Resources/Lexicon/common-phrases.tsv")
        )
        return lex
    }()

    @Test func doesNotConfuseFlatAndRetroflex() {
        #expect(!PinyinFuzzyCorrector.neighbors(of: "zong").contains("zhong"))
        #expect(!PinyinFuzzyCorrector.neighbors(of: "zhong").contains("zong"))
        #expect(!PinyinFuzzyCorrector.neighbors(of: "si").contains("shi"))
        #expect(!PinyinFuzzyCorrector.neighbors(of: "shi").contains("si"))
        #expect(!PinyinFuzzyCorrector.neighbors(of: "cai").contains("chai"))
        #expect(!PinyinFuzzyCorrector.neighbors(of: "chai").contains("cai"))
    }

    @Test func neighborsStillCoverOptionalNasalAndNL() {
        #expect(PinyinFuzzyCorrector.neighbors(of: "xin").contains("xing"))
        #expect(PinyinFuzzyCorrector.neighbors(of: "xing").contains("xin"))
        #expect(PinyinFuzzyCorrector.neighbors(of: "ban").contains("bang"))
        #expect(PinyinFuzzyCorrector.neighbors(of: "ni").contains("li"))
    }

    @Test func recoverUnsegmentableOnlyUsesAdjacentSwap() {
        #expect(PinyinFuzzyCorrector.recoverUnsegmentable("chnag") == ["chang"])
        // Flat-tongue legal codes are not rewritten into zh forms.
        #expect(PinyinFuzzyCorrector.recoverUnsegmentable("zongguo").isEmpty)
    }

    @Test func standardPinyinKeepsZhongGuoExact() {
        #expect(Self.lexicon.isReady)
        let exact = PhraseComposer.compose(
            rawInput: "zhongguo",
            lexicon: Self.lexicon,
            fuzzyEnabled: false
        )
        #expect(exact?.text == "中国")
        #expect(exact?.fuzzyEdits == 0)

        // Flat-tongue typing must not silently become 中国 when fuzzy is off.
        let flat = PhraseComposer.compose(
            rawInput: "zongguo",
            lexicon: Self.lexicon,
            fuzzyEnabled: false
        )
        if let flat {
            #expect(flat.text != "中国")
        }
    }

    @Test func defaultsToDisabled() {
        let name = "app.vibevoice.oss.fuzzy-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        #expect(PinyinFuzzyCorrector.isEnabled(defaults: defaults) == false)
    }
}
