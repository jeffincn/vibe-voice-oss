import Foundation
import Testing
@testable import VibeVoicePinyin

struct PinyinTypoCorrectorTests {
    @Test func stripsNonLatinAndLowercases() {
        #expect(PinyinTypoCorrector.latinCode(from: "真实 ChNag ") == "chnag")
    }

    @Test func adjacentSwapRecoversChang() {
        #expect(PinyinTypoCorrector.correctAdjacentSwap("chnag") == "chang")
    }

    @Test func adjacentSwapRecoversNihaoStyleTranspose() {
        #expect(PinyinTypoCorrector.correctAdjacentSwap("nihao") == nil)
        #expect(PinyinTypoCorrector.correctAdjacentSwap("niaho") == "nihao")
    }

    @Test func legalInputIsNotCorrected() {
        #expect(PinyinTypoCorrector.correctAdjacentSwap("chang") == nil)
        #expect(PinyinTypoCorrector.correctAdjacentSwap("cha") == nil)
        #expect(PinyinTypoCorrector.correctAdjacentSwap("chan") == nil)
        #expect(PinyinTypoCorrector.correctAdjacentSwap("nihao") == nil)
    }

    @Test func tooShortIsIgnored() {
        #expect(PinyinTypoCorrector.correctAdjacentSwap("ab") == nil)
        #expect(PinyinTypoCorrector.correctAdjacentSwap("cn") == nil)
    }

    @Test func canSegmentValidAndInvalid() {
        #expect(PinyinTypoCorrector.canSegment("chang"))
        #expect(PinyinTypoCorrector.canSegment("cha", allowTrailingPrefix: true))
        #expect(!PinyinTypoCorrector.canSegment("chnag", allowTrailingPrefix: true))
        #expect(PinyinTypoCorrector.canSegment("woaini"))
    }

    @Test func syllableTableContainsCoreSyllables() {
        #expect(PinyinSyllableTable.isSyllable("chang"))
        #expect(PinyinSyllableTable.isSyllable("ni"))
        #expect(PinyinSyllableTable.isSyllable("hao"))
        #expect(PinyinSyllableTable.isSyllable("zhong"))
        #expect(PinyinSyllableTable.isSyllable("nv"))
        #expect(!PinyinSyllableTable.isSyllable("chnag"))
        #expect(PinyinSyllableTable.isPrefix("ch"))
        #expect(PinyinSyllableTable.isPrefix("cha"))
    }

    @Test func adjacentSwapRecoversLongPhraseWithInteriorTranspose() {
        // User typed xiwnag… intending xiwang… (希望想要的逻辑)
        let typed = "xiwnagxiangyaodeluoji"
        #expect(PinyinTypoCorrector.correctAdjacentSwap(typed) == "xiwangxiangyaodeluoji")
        #expect(PinyinTypoCorrector.correctAdjacentSwap("xiwnag") == "xiwang")
    }
}
