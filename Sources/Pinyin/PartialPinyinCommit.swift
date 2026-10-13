import Foundation

/// Helpers for keeping unused pinyin after a partial candidate commit.
///
/// Selecting a shorter word from a longer syllable sequence must leave the
/// remaining code in composition so the user can keep choosing — the classic
/// IME “confirm prefix, continue” flow.
public enum PartialPinyinCommit {
    /// Latin syllables still unused after confirming `committedText`.
    /// Returns `nil` when the commit looks complete, mixed (ASCII letters), or
    /// the syllable lattice cannot be recovered safely.
    public static func remainingCode(
        afterCommitting committedText: String,
        rawInput: String
    ) -> String? {
        let latin = PinyinTypoCorrector.latinCode(from: rawInput)
        guard !latin.isEmpty else { return nil }

        // Mixed English / proper-noun commits do not map 1:1 to syllables.
        if committedText.contains(where: { $0.isASCII && $0.isLetter }) {
            return nil
        }

        let cjkCount = committedText.filter { !$0.isASCII }.count
        guard cjkCount > 0 else { return nil }
        guard let syllables = PhraseComposer.segmentSyllables(latin), !syllables.isEmpty else {
            return nil
        }
        guard cjkCount < syllables.count else { return nil }
        return syllables[cjkCount...].joined()
    }

    /// Deduplicate by text while preferring a real Rime row (`engineIndex >= 0`)
    /// over a synthesised peer, so selection can go through librime's partial
    /// confirm path instead of a full clear.
    public static func preferRimeRows(_ candidates: [RimeCandidate]) -> [RimeCandidate] {
        var best: [String: RimeCandidate] = [:]
        var order: [String] = []
        for candidate in candidates {
            if let existing = best[candidate.text] {
                if existing.engineIndex < 0 && candidate.engineIndex >= 0 {
                    best[candidate.text] = candidate
                }
            } else {
                best[candidate.text] = candidate
                order.append(candidate.text)
            }
        }
        return order.compactMap { best[$0] }
    }
}
