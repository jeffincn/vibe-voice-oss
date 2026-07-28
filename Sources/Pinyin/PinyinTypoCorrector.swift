import Foundation

/// Recovers a typed pinyin string that failed syllable segmentation by trying
/// a single adjacent-letter swap (scope A). Does not rewrite the IME preedit;
/// callers look up candidates for the corrected code separately (presentation A).
public enum PinyinTypoCorrector {
    public static let minimumLength = 3
    public static let typoFixSource = "typo_fix"

    /// Latin letters only, lowercased, with spaces / apostrophes stripped.
    public static func latinCode(from raw: String) -> String {
        var result = ""
        result.reserveCapacity(raw.count)
        for character in raw.lowercased() {
            guard character.isASCII, character.isLetter else { continue }
            result.append(character)
        }
        return result
    }

    /// Whether `code` can be consumed as complete legal syllables, optionally
    /// ending with one incomplete-but-legal syllable prefix (mid-typing).
    public static func canSegment(_ code: String, allowTrailingPrefix: Bool = true) -> Bool {
        guard !code.isEmpty else { return true }
        return segmentability(code, allowTrailingPrefix: allowTrailingPrefix) != nil
    }

    /// Best single adjacent-swap correction, or `nil` when the input already
    /// fully segments into complete syllables, is too short, or no swap yields
    /// a legal segmentation.
    ///
    /// The "already OK" check requires *complete* syllables only. Allowing a
    /// trailing prefix there would treat typos like `niaho` (`ni|a|ho`) as
    /// valid mid-typing and skip recovery of `nihao`.
    public static func correctAdjacentSwap(_ raw: String) -> String? {
        let code = latinCode(from: raw)
        guard code.count >= minimumLength else { return nil }
        if canSegment(code, allowTrailingPrefix: false) { return nil }

        var best: String?
        var bestScore = Int.min
        let chars = Array(code)
        for index in 0..<(chars.count - 1) {
            guard chars[index] != chars[index + 1] else { continue }
            var swapped = chars
            swapped.swapAt(index, index + 1)
            let candidate = String(swapped)
            guard let score = segmentability(candidate, allowTrailingPrefix: true) else { continue }
            // Full syllable cuts always beat a trailing-prefix parse so
            // `niaho` → `nihao` wins over `niaoh` (`ni|ao|h`).
            let ranked = score.full
                ? 1_000_000 + score.syllables * 1_000
                : score.syllables * 1_000
            if ranked > bestScore
                || (ranked == bestScore && (best == nil || candidate < best!)) {
                bestScore = ranked
                best = candidate
            }
        }
        return best
    }

    // MARK: - Segmentation

    private struct SegmentScore: Equatable {
        let syllables: Int
        let full: Bool
    }

    /// Returns a score when the whole string is covered; `nil` otherwise.
    private static func segmentability(
        _ code: String,
        allowTrailingPrefix: Bool
    ) -> SegmentScore? {
        let chars = Array(code)
        let n = chars.count
        // dp[i] = best syllable count covering code[0..<i], preferring full cuts.
        var bestCount = Array(repeating: -1, count: n + 1)
        var bestFull = Array(repeating: false, count: n + 1)
        bestCount[0] = 0
        bestFull[0] = true

        for start in 0..<n where bestCount[start] >= 0 {
            var piece = ""
            for end in (start + 1)...n {
                piece.append(chars[end - 1])
                let isSyl = PinyinSyllableTable.isSyllable(piece)
                let isPref = allowTrailingPrefix && end == n && PinyinSyllableTable.isPrefix(piece)
                guard isSyl || isPref else {
                    // Keep scanning only while `piece` is still a prefix of some syllable;
                    // otherwise longer extensions cannot become legal from this start.
                    if !PinyinSyllableTable.isPrefix(piece) { break }
                    continue
                }
                let nextCount = bestCount[start] + (isSyl || isPref ? 1 : 0)
                let nextFull = bestFull[start] && isSyl
                // Prefer a fully-syllable parse over one that leans on a trailing
                // prefix, even when the prefix path counts more pieces
                // (`xi|wang` beats `xi|wan|g`).
                let better: Bool
                if bestCount[end] < 0 {
                    better = true
                } else if nextFull != bestFull[end] {
                    better = nextFull
                } else {
                    better = nextCount > bestCount[end]
                }
                if better {
                    bestCount[end] = nextCount
                    bestFull[end] = nextFull
                }
            }
        }

        guard bestCount[n] >= 0 else { return nil }
        return SegmentScore(syllables: bestCount[n], full: bestFull[n])
    }
}
