import Foundation
import Testing
@testable import VibeVoicePinyin

struct PhraseComposerTests {
    private static let repoRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }()

    private static let lexicon: PinyinLexicon = {
        let lex = PinyinLexicon()
        let url = repoRoot.appendingPathComponent("Resources/InputMethod/RimeData/pinyin_simp.dict.yaml")
        lex.loadSynchronously(
            from: url,
            phraseOverlayURL: repoRoot.appendingPathComponent("Resources/InputMethod/Lexicon/common-phrases.tsv")
        )
        return lex
    }()

    private static let external: ExternalLexicon = {
        let ext = ExternalLexicon()
        ext.loadSynchronously(
            properURL: repoRoot.appendingPathComponent("Resources/InputMethod/Lexicon/proper-nouns.tsv"),
            termsURL: repoRoot.appendingPathComponent("Resources/InputMethod/Lexicon/tech-terms.tsv"),
            zhURL: repoRoot.appendingPathComponent("Resources/InputMethod/Lexicon/term-zh.tsv")
        )
        return ext
    }()

    @Test func lexiconIndexesMultiSyllableEntries() {
        #expect(Self.lexicon.isReady)
        let yiChu = Self.lexicon.entries(forCompactCode: "yichu")
        #expect(yiChu.contains(where: { $0.text == "移除" }))
        let liMian = Self.lexicon.bestEntry(forCompactCode: "limian")
        #expect(liMian?.text == "里面")
    }

    @Test func segmentsCommonPinyin() {
        let syllables = PhraseComposer.segmentSyllables("yichulimiandedaima")
        #expect(syllables == ["yi", "chu", "li", "mian", "de", "dai", "ma"])
    }

    @Test func contextPrefersRemoveInsideCode() {
        let result = PhraseComposer.compose(
            rawInput: "yichulimiandedaima",
            documentContext: "你有没有改",
            lexicon: Self.lexicon
        )
        #expect(result?.text == "移除里面的代码")
    }

    @Test func mixedCoreMLComposition() {
        let result = MixedTokenAnalyzer.compose(
            rawInput: "woxiangyongcoremlzuohouxuanpaixu",
            documentContext: "",
            style: .developer,
            lexicon: Self.lexicon,
            external: Self.external
        )
        #expect(result != nil)
        #expect(result?.hasProperNoun == true)
        #expect(result?.text.contains("Core ML") == true)
        #expect(result?.text.contains("想") == true)
        // Exact user-visible shape: Chinese + spaced Core ML + Chinese.
        #expect(result?.text.contains("Core ML") == true)
        #expect(result?.text.hasPrefix("我想用") == true)
    }

    @Test func embedsTabEnglishInsidePinyin() {
        let result = MixedTokenAnalyzer.compose(
            rawInput: "woxiwangkeyiyongtablaiqiehuan",
            documentContext: "",
            style: .developer,
            lexicon: Self.lexicon,
            external: Self.external
        )
        #expect(result != nil)
        #expect(result?.hasEnglish == true)
        #expect(result?.text.lowercased().contains("tab") == true)
        #expect(result?.text.contains("巴黎") != true)
        #expect(result?.text.contains("希望") == true)
        #expect(result?.text.contains("切换") == true)
    }

    @Test func doesNotTreatYouAsEnglish() {
        let result = MixedTokenAnalyzer.compose(
            rawInput: "woyoushiyaozuo",
            documentContext: "",
            style: .developer,
            lexicon: Self.lexicon,
            external: Self.external
        )
        if let result {
            #expect(result.hasEnglish == false)
            #expect(!result.text.lowercased().contains("you"))
        }
    }

    @Test func smartChineseTranslatesCommonTerms() {
        let tokens = [
            MixedToken(kind: .pinyinWord, code: "zuo", display: "做", weight: 1),
            MixedToken(kind: .englishTerm, code: "candidatererank", display: "candidate rerank", weight: 1),
        ]
        let rendered = MixedTokenAnalyzer.render(tokens, style: .smartChinese, external: Self.external)
        #expect(rendered.contains("候选重排序"))
    }
}
