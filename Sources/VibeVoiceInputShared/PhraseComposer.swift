import Foundation

/// Source tag for synthesised phrase-reasoning candidates injected into the bar.
public enum ReasoningCandidate {
    public static let source = "reason"
}

/// Pure-pinyin Viterbi composer: syllable lattice → dictionary words → scored
/// full-line text, with a light left-context continuation bonus on the first word.
public enum PhraseComposer {
    public struct Result: Equatable, Sendable {
        public let text: String
        public let score: Double
        public let wordCount: Int
        public let confidence: Confidence
        /// How many flat/retroflex / n-l / nasal fuzzy edits were applied.
        public let fuzzyEdits: Int

        public enum Confidence: Equatable, Sendable {
            case high
            case medium
            case low
        }
    }

    /// Verbs / stems that, when they end the left context, prefer action words.
    private static let actionContextSuffixes = [
        "有没有改", "改", "删", "删除", "写", "要", "做", "加", "去掉", "拿掉",
    ]

    private static let preferredFirstWords: Set<String> = [
        "移除", "删除", "修改", "更改", "替换", "更新", "添加", "写入", "去掉", "清除",
    ]

    private static let demotedFirstWords: Set<String> = [
        "一处", "一出", "一", "溢出", "益处", "衣橱",
    ]

    /// Compose the best full-line Chinese phrase for a continuous pinyin string.
    /// Fuzzy accent variants (n/l, nasals — never flat/retroflex) are opt-in only.
    public static func compose(
        rawInput: String,
        documentContext: String = "",
        lexicon: PinyinLexicon = .shared,
        maxSyllables: Int = 24,
        fuzzyEnabled: Bool = PinyinFuzzyCorrector.isEnabled()
    ) -> Result? {
        guard lexicon.isReady else { return nil }
        let latin = PinyinTypoCorrector.latinCode(from: rawInput)
        guard latin.count >= 4 else { return nil }

        var syllablePaths: [(syllables: [String], edits: Int)] = []
        if let exact = segmentSyllables(latin), !exact.isEmpty, exact.count <= maxSyllables {
            if fuzzyEnabled {
                for variant in PinyinFuzzyCorrector.variants(of: exact, maxEdits: 2) where variant.syllables.count <= maxSyllables {
                    syllablePaths.append((variant.syllables, variant.editCount))
                }
            } else {
                syllablePaths.append((exact, 0))
            }
        } else if fuzzyEnabled {
            for recovered in PinyinFuzzyCorrector.recoverUnsegmentable(latin) {
                if let syllables = segmentSyllables(recovered), !syllables.isEmpty,
                   syllables.count <= maxSyllables {
                    syllablePaths.append((syllables, 1))
                    if fuzzyEnabled {
                        for variant in PinyinFuzzyCorrector.variants(of: syllables, maxEdits: 1) {
                            syllablePaths.append((variant.syllables, 1 + variant.editCount))
                        }
                    }
                }
            }
        }

        // Deduplicate identical syllable joins, keep lowest edit cost.
        var bestEditsForCode: [String: (syllables: [String], edits: Int)] = [:]
        for path in syllablePaths {
            let key = path.syllables.joined()
            if let existing = bestEditsForCode[key] {
                if path.edits < existing.edits {
                    bestEditsForCode[key] = path
                }
            } else {
                bestEditsForCode[key] = path
            }
        }

        var best: Result?
        for (_, path) in bestEditsForCode {
            guard let scored = viterbi(
                syllables: path.syllables,
                lexicon: lexicon,
                documentContext: documentContext
            ), !scored.words.isEmpty else { continue }
            let text = scored.words.map(\.text).joined()
            guard text.count >= 2 else { continue }

            // Penalise fuzzy edits so exact input still wins when both are plausible.
            let adjusted = scored.score - Double(path.edits) * 3.5
            let confidence: Result.Confidence
            if path.edits == 0, (scored.usedContextBonus || scored.words.count >= 3) {
                confidence = .high
            } else if path.edits == 0, scored.words.count >= 2 {
                confidence = .medium
            } else if path.edits <= 1, scored.words.count >= 2, scored.usedContextBonus {
                confidence = .high
            } else if path.edits <= 1, scored.words.count >= 2 {
                confidence = .medium
            } else if path.edits <= 2, text.count >= 3 {
                confidence = .medium
            } else {
                confidence = .low
            }
            let candidate = Result(
                text: text,
                score: adjusted,
                wordCount: scored.words.count,
                confidence: confidence,
                fuzzyEdits: path.edits
            )
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }

    // MARK: - Syllable segmentation

    /// Greedy-longest DP over `PinyinSyllableTable` covering the whole string.
    public static func segmentSyllables(_ code: String) -> [String]? {
        let chars = Array(code)
        let n = chars.count
        var bestLen = Array(repeating: -1, count: n + 1)
        var prev = Array(repeating: -1, count: n + 1)
        bestLen[0] = 0
        for start in 0..<n where bestLen[start] >= 0 {
            var piece = ""
            for end in (start + 1)...min(n, start + 6) {
                piece.append(chars[end - 1])
                guard PinyinSyllableTable.isPrefix(piece) else { break }
                guard PinyinSyllableTable.isSyllable(piece) else { continue }
                let nextCount = bestLen[start] + 1
                // Prefer fewer syllables (longer cuts) when ties appear.
                if bestLen[end] < 0
                    || nextCount < bestLen[end]
                    || (nextCount == bestLen[end] && (end - start) > (end - prev[end])) {
                    bestLen[end] = nextCount
                    prev[end] = start
                }
            }
        }
        guard bestLen[n] >= 0 else { return nil }
        var syllables: [String] = []
        var cursor = n
        while cursor > 0 {
            let start = prev[cursor]
            guard start >= 0 else { return nil }
            syllables.append(String(chars[start..<cursor]))
            cursor = start
        }
        return syllables.reversed()
    }

    // MARK: - Viterbi

    private struct WordPick {
        let text: String
        let weight: Int
        let syllableCount: Int
    }

    private struct Path {
        let words: [WordPick]
        let score: Double
        let usedContextBonus: Bool
    }

    private static func viterbi(
        syllables: [String],
        lexicon: PinyinLexicon,
        documentContext: String
    ) -> Path? {
        let n = syllables.count
        // best[i] = best path covering syllables[0..<i]
        var bestScore = Array(repeating: -Double.infinity, count: n + 1)
        var bestPrev = Array(repeating: -1, count: n + 1)
        var bestWord: [WordPick?] = Array(repeating: nil, count: n + 1)
        var bestUsedContext = Array(repeating: false, count: n + 1)
        bestScore[0] = 0

        let wantsAction = actionContextSuffixes.contains { documentContext.hasSuffix($0) }

        for start in 0..<n where bestScore[start].isFinite {
            for end in (start + 1)...min(n, start + 6) {
                let slice = syllables[start..<end]
                let compact = slice.joined()
                let entries = lexicon.entries(forCompactCode: compact)
                var candidates: [WordPick]
                if entries.isEmpty {
                    // Single-syllable fallback via best single-char or the syllable itself.
                    if end - start == 1 {
                        if let entry = lexicon.bestEntry(forCompactCode: compact) {
                            candidates = [WordPick(text: entry.text, weight: entry.weight, syllableCount: 1)]
                        } else {
                            continue
                        }
                    } else {
                        continue
                    }
                } else {
                    candidates = entries.prefix(8).map {
                        WordPick(text: $0.text, weight: $0.weight, syllableCount: end - start)
                    }
                    // Context-preferred verbs may sit far down the weight list
                    // (e.g. 移除 at 267). Always inject them when present.
                    if start == 0 {
                        for entry in entries where preferredFirstWords.contains(entry.text) {
                            if !candidates.contains(where: { $0.text == entry.text }) {
                                candidates.append(WordPick(
                                    text: entry.text,
                                    weight: entry.weight,
                                    syllableCount: end - start
                                ))
                            }
                        }
                    }
                }

                for word in candidates {
                    var edge = log(1.0 + Double(max(word.weight, 1)))
                    if word.syllableCount >= 2 {
                        edge += Double(word.syllableCount) * 4.5  // strong multi-syllable preference
                        edge += 6.0
                    } else {
                        edge -= 5.0  // single-char is last-resort glue
                        // Mild extra penalty when gluing a singleton onto a
                        // multi-syllable word (魔法+帮), without killing valid
                        // tails like 我想+用.
                        if start > 0, let prev = bestWord[start], prev.syllableCount >= 2 {
                            edge -= 4.0
                        }
                    }
                    edge -= 0.35  // per-word segmentation penalty
                    // Full-span compounds that cover the whole utterance win hard.
                    if start == 0, end == n, word.syllableCount >= 2 {
                        edge += 14.0 + Double(word.syllableCount) * 2.0
                    }

                    var usedContext = bestUsedContext[start]
                    if start == 0 {
                        if wantsAction, preferredFirstWords.contains(word.text) {
                            edge += 20.0
                            usedContext = true
                        }
                        if wantsAction, demotedFirstWords.contains(word.text) {
                            edge -= 12.0
                        }
                    }

                    let total = bestScore[start] + edge
                    if total > bestScore[end] {
                        bestScore[end] = total
                        bestPrev[end] = start
                        bestWord[end] = word
                        bestUsedContext[end] = usedContext
                    }
                }
            }
        }

        guard bestScore[n].isFinite else { return nil }
        var words: [WordPick] = []
        var cursor = n
        while cursor > 0 {
            guard let word = bestWord[cursor], bestPrev[cursor] >= 0 else { return nil }
            words.append(word)
            cursor = bestPrev[cursor]
        }
        return Path(
            words: words.reversed(),
            score: bestScore[n],
            usedContextBonus: bestUsedContext[n]
        )
    }
}
