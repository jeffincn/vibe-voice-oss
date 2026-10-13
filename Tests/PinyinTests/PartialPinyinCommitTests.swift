import Testing
@testable import VibeVoicePinyin

@Suite("PartialPinyinCommit")
struct PartialPinyinCommitTests {
    @Test func remainingCodeKeepsUnusedSyllablesAfterPrefixCommit() {
        let remaining = PartialPinyinCommit.remainingCode(
            afterCommitting: "你好",
            rawInput: "nihaoshijie"
        )
        #expect(remaining == "shijie")
    }

    @Test func remainingCodeNilWhenFullyConsumed() {
        let remaining = PartialPinyinCommit.remainingCode(
            afterCommitting: "你好世界",
            rawInput: "nihaoshijie"
        )
        #expect(remaining == nil)
    }

    @Test func remainingCodeNilForMixedEnglishCommit() {
        let remaining = PartialPinyinCommit.remainingCode(
            afterCommitting: "用CoreML",
            rawInput: "yongcoremlzuo"
        )
        #expect(remaining == nil)
    }

    @Test func preferRimeRowsKeepsEngineIndexOverSynthetic() {
        let synthetic = RimeCandidate(
            text: "你好世界",
            engineIndex: -1,
            source: ReasoningCandidate.source
        )
        let rime = RimeCandidate(text: "你好世界", engineIndex: 2)
        let other = RimeCandidate(text: "你好", engineIndex: 3)
        let result = PartialPinyinCommit.preferRimeRows([synthetic, rime, other])
        #expect(result.map(\.text) == ["你好世界", "你好"])
        #expect(result[0].engineIndex == 2)
        #expect(result[0].source == nil)
    }
}
