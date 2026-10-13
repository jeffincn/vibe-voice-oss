import Foundation

/// Complete Hanyu Pinyin syllable inventory for typed (ASCII) input.
/// Matches full-pinyin spelling as used by Rime `vibe_pinyin` (ü → `v` / `u`
/// after j/q/x/y). Used only for typo segmentation — not as a dictionary.
public enum PinyinSyllableTable {
    public static let syllables: Set<String> = {
        var set = Set<String>()
        set.formUnion(zeroInitial)
        set.formUnion(withInitial)
        return set
    }()

    /// Every non-empty prefix of a legal syllable (including the syllable).
    public static let prefixes: Set<String> = {
        var set = Set<String>()
        for syllable in syllables {
            var prefix = ""
            for character in syllable {
                prefix.append(character)
                set.insert(prefix)
            }
        }
        return set
    }()

    public static func isSyllable(_ text: String) -> Bool {
        syllables.contains(text)
    }

    public static func isPrefix(_ text: String) -> Bool {
        prefixes.contains(text)
    }

    // MARK: - Inventory

    private static let zeroInitial: Set<String> = [
        "a", "ai", "an", "ang", "ao",
        "e", "ei", "en", "eng", "er",
        "o", "ou",
        "yi", "ya", "ye", "yao", "you", "yan", "yin", "yang", "ying", "yong",
        "wu", "wa", "wo", "wai", "wei", "wan", "wen", "wang", "weng",
        "yu", "yue", "yuan", "yun",
    ]

    private static let withInitial: Set<String> = {
        var set = Set<String>()

        let groupBPMF: [(String, [String])] = [
            ("b", ["a", "ai", "an", "ang", "ao", "ei", "en", "eng", "i", "ian", "iao", "ie", "in", "ing", "o", "u"]),
            ("p", ["a", "ai", "an", "ang", "ao", "ei", "en", "eng", "i", "ian", "iao", "ie", "in", "ing", "o", "ou", "u"]),
            ("m", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "i", "ian", "iao", "ie", "in", "ing", "iu", "o", "ou", "u"]),
            ("f", ["a", "an", "ang", "ei", "en", "eng", "o", "ou", "u"]),
        ]
        let groupDTNL: [(String, [String])] = [
            ("d", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "i", "ia", "ian", "iao", "ie", "ing", "iu", "ong", "ou", "u", "uan", "ui", "un", "uo"]),
            ("t", ["a", "ai", "an", "ang", "ao", "e", "ei", "eng", "i", "ian", "iao", "ie", "ing", "ong", "ou", "u", "uan", "ui", "un", "uo"]),
            ("n", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "i", "ian", "iang", "iao", "ie", "in", "ing", "iu", "ong", "ou", "u", "uan", "un", "uo", "v", "ve"]),
            ("l", ["a", "ai", "an", "ang", "ao", "e", "ei", "eng", "i", "ia", "ian", "iang", "iao", "ie", "in", "ing", "iu", "o", "ong", "ou", "u", "uan", "un", "uo", "v", "ve"]),
        ]
        let groupGKH: [(String, [String])] = [
            ("g", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "ong", "ou", "u", "ua", "uai", "uan", "uang", "ui", "un", "uo"]),
            ("k", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "ong", "ou", "u", "ua", "uai", "uan", "uang", "ui", "un", "uo"]),
            ("h", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "ong", "ou", "u", "ua", "uai", "uan", "uang", "ui", "un", "uo"]),
        ]
        let groupJQXY: [(String, [String])] = [
            ("j", ["i", "ia", "ian", "iang", "iao", "ie", "in", "ing", "iong", "iu", "u", "uan", "ue", "un"]),
            ("q", ["i", "ia", "ian", "iang", "iao", "ie", "in", "ing", "iong", "iu", "u", "uan", "ue", "un"]),
            ("x", ["i", "ia", "ian", "iang", "iao", "ie", "in", "ing", "iong", "iu", "u", "uan", "ue", "un"]),
        ]
        let groupZCSR: [(String, [String])] = [
            ("zh", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "i", "ong", "ou", "u", "ua", "uai", "uan", "uang", "ui", "un", "uo"]),
            ("ch", ["a", "ai", "an", "ang", "ao", "e", "en", "eng", "i", "ong", "ou", "u", "ua", "uai", "uan", "uang", "ui", "un", "uo"]),
            ("sh", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "i", "ou", "u", "ua", "uai", "uan", "uang", "ui", "un", "uo"]),
            ("r", ["an", "ang", "ao", "e", "en", "eng", "i", "ong", "ou", "u", "ua", "uan", "ui", "un", "uo"]),
            ("z", ["a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "i", "ong", "ou", "u", "uan", "ui", "un", "uo"]),
            ("c", ["a", "ai", "an", "ang", "ao", "e", "en", "eng", "i", "ong", "ou", "u", "uan", "ui", "un", "uo"]),
            ("s", ["a", "ai", "an", "ang", "ao", "e", "en", "eng", "i", "ong", "ou", "u", "uan", "ui", "un", "uo"]),
        ]

        for group in [groupBPMF, groupDTNL, groupGKH, groupJQXY, groupZCSR] {
            for (initial, finals) in group {
                for final in finals {
                    set.insert(initial + final)
                }
            }
        }
        return set
    }()
}
