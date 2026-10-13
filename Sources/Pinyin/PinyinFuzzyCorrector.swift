import Foundation

/// Optional light accent tolerance (n/l, nasals only). Flat/retroflex (z/zh,
/// c/ch, s/sh) is intentionally **not** supported — mixing those made standard
/// spelling worse for users who type correct retroflex initials.
///
/// Default is **off**. Adjacent-letter swap recovery lives in `PinyinTypoCorrector`.
public enum PinyinFuzzyCorrector {
    public static let defaultsKey = "fuzzyPinyinEnabled"
    /// Bumped when flat/retroflex support was removed so old default-ON prefs reset.
    private static let migrationKey = "fuzzyPinyinNoRetroflexMigration"

    public static func isEnabled(
        defaults: UserDefaults? = UserDefaults(suiteName: CandidateRankerFactory.defaultsSuiteName)
    ) -> Bool {
        guard let defaults else { return false }
        migrateIfNeeded(defaults: defaults)
        if defaults.object(forKey: defaultsKey) == nil { return false }
        return defaults.bool(forKey: defaultsKey)
    }

    public static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults? = UserDefaults(suiteName: CandidateRankerFactory.defaultsSuiteName)
    ) {
        defaults?.set(enabled, forKey: defaultsKey)
        defaults?.set(true, forKey: migrationKey)
    }

    /// One-shot: turn off installs that still have the old Cantonese flat/retroflex default.
    private static func migrateIfNeeded(defaults: UserDefaults) {
        guard defaults.object(forKey: migrationKey) == nil else { return }
        defaults.set(false, forKey: defaultsKey)
        defaults.set(true, forKey: migrationKey)
    }

    public struct Variant: Equatable, Sendable {
        public let syllables: [String]
        public let editCount: Int
        public let code: String

        public init(syllables: [String], editCount: Int) {
            self.syllables = syllables
            self.editCount = editCount
            self.code = syllables.joined()
        }
    }

    /// Fuzzy neighbours of one legal syllable (edit cost 1 each).
    /// Does **not** include z↔zh / c↔ch / s↔sh.
    public static func neighbors(of syllable: String) -> [String] {
        var result: Set<String> = []

        // Initial: n↔l
        if syllable.hasPrefix("n") && !syllable.hasPrefix("ng") {
            result.insert("l" + syllable.dropFirst())
        } else if syllable.hasPrefix("l") {
            result.insert("n" + syllable.dropFirst())
        }

        // Finals: in↔ing, en↔eng, an↔ang (+ ian/iang, uan/uang).
        if let swapped = swapFinal(syllable) {
            result.insert(swapped)
        }

        return result.filter { $0 != syllable && PinyinSyllableTable.isSyllable($0) }.sorted()
    }

    private static func swapFinal(_ syllable: String) -> String? {
        let finals = ["iang", "uang", "ing", "eng", "ang", "ian", "uan", "in", "en", "an"]
        guard let matched = finals.first(where: { syllable.hasSuffix($0) }) else { return nil }
        let pairs: [String: String] = [
            "iang": "ian", "ian": "iang",
            "uang": "uan", "uan": "uang",
            "ing": "in", "in": "ing",
            "eng": "en", "en": "eng",
            "ang": "an", "an": "ang",
        ]
        guard let other = pairs[matched] else { return nil }
        return String(syllable.dropLast(matched.count)) + other
    }

    /// Expand a syllable path with at most `maxEdits` fuzzy substitutions.
    public static func variants(
        of syllables: [String],
        maxEdits: Int = 2,
        maxVariants: Int = 48
    ) -> [Variant] {
        guard !syllables.isEmpty else { return [] }
        var seen = Set<String>()
        var results: [Variant] = []

        func append(_ path: [String], edits: Int) {
            let key = path.joined(separator: "|")
            guard seen.insert(key).inserted else { return }
            results.append(Variant(syllables: path, editCount: edits))
        }

        append(syllables, edits: 0)
        guard maxEdits > 0 else { return results }

        for index in syllables.indices {
            for neighbor in neighbors(of: syllables[index]) {
                var path = syllables
                path[index] = neighbor
                append(path, edits: 1)
                if results.count >= maxVariants { return results }
            }
        }

        guard maxEdits > 1, syllables.count <= 10 else { return results }
        for i in syllables.indices {
            let ni = neighbors(of: syllables[i])
            guard !ni.isEmpty else { continue }
            for j in syllables.indices where j > i {
                let nj = neighbors(of: syllables[j])
                guard !nj.isEmpty else { continue }
                for a in ni {
                    for b in nj {
                        var path = syllables
                        path[i] = a
                        path[j] = b
                        append(path, edits: 2)
                        if results.count >= maxVariants { return results }
                    }
                }
            }
        }
        return results
    }

    /// When the typed code does not segment, only try adjacent-letter swap.
    /// No flat/retroflex digraph rewriting.
    public static func recoverUnsegmentable(_ raw: String) -> [String] {
        let code = PinyinTypoCorrector.latinCode(from: raw)
        guard code.count >= 3 else { return [] }
        guard let swapped = PinyinTypoCorrector.correctAdjacentSwap(code),
              swapped != code,
              PinyinTypoCorrector.canSegment(swapped, allowTrailingPrefix: false) else {
            return []
        }
        return [swapped]
    }
}
