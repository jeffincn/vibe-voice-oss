import Foundation
import VibeVoiceShared

/// How mixed Chinese + English compositions should be rendered before display.
public enum MixedOutputStyle: String, CaseIterable, Sendable, Codable {
    case developer
    case smartChinese
    case original

    public static let defaultsKey = "mixedOutputStyle"

    public static func load(
        defaults: UserDefaults? = UserDefaults(suiteName: CandidateRankerFactory.defaultsSuiteName)
    ) -> MixedOutputStyle {
        guard let raw = defaults?.string(forKey: defaultsKey),
              let style = MixedOutputStyle(rawValue: raw) else {
            return .developer
        }
        return style
    }

    public static func save(
        _ style: MixedOutputStyle,
        defaults: UserDefaults? = UserDefaults(suiteName: CandidateRankerFactory.defaultsSuiteName)
    ) {
        defaults?.set(style.rawValue, forKey: defaultsKey)
    }
}

public enum MixedTokenKind: Equatable, Sendable {
    case pinyinWord
    case properNoun
    case englishTerm
}

public struct MixedToken: Equatable, Sendable {
    public let kind: MixedTokenKind
    public let code: String
    public let display: String
    public let weight: Double

    public init(kind: MixedTokenKind, code: String, display: String, weight: Double) {
        self.kind = kind
        self.code = code
        self.display = display
        self.weight = weight
    }
}

public struct MixedComposition: Equatable, Sendable {
    public let text: String
    public let tokens: [MixedToken]
    public let score: Double
    public let confidence: PhraseComposer.Result.Confidence
    public let hasProperNoun: Bool
    public let hasEnglish: Bool
    public let fuzzyEdits: Int

    public init(
        text: String,
        tokens: [MixedToken],
        score: Double,
        confidence: PhraseComposer.Result.Confidence,
        hasProperNoun: Bool,
        hasEnglish: Bool,
        fuzzyEdits: Int = 0
    ) {
        self.text = text
        self.tokens = tokens
        self.score = score
        self.confidence = confidence
        self.hasProperNoun = hasProperNoun
        self.hasEnglish = hasEnglish
        self.fuzzyEdits = fuzzyEdits
    }
}

/// Loads proper-noun / tech-term / zh-translation tables shipped under Resources/InputMethod/Lexicon.
public final class ExternalLexicon: @unchecked Sendable {
    public static let shared = ExternalLexicon()

    private let lock = NSLock()
    private var proper: [String: String] = [:]
    private var terms: [String: String] = [:]
    private var termZH: [String: String] = [:]
    private var project: [String: String] = [:]
    private var ready = false

    public var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready
    }

    public func ensureLoaded(bundle: Bundle = .main) {
        lock.lock()
        if ready {
            lock.unlock()
            return
        }
        lock.unlock()
        var properMap = Self.loadTSV(named: "proper-nouns", subdirectory: "Lexicon", bundle: bundle)
        var termMap = Self.loadTSV(named: "tech-terms", subdirectory: "Lexicon", bundle: bundle)
        let zhMap = Self.loadTSV(named: "term-zh", subdirectory: "Lexicon", bundle: bundle)
        var projectMap = Self.loadProjectTSV()
        Self.mergeSharedCorrections(proper: &properMap, terms: &termMap, project: &projectMap)
        lock.lock()
        proper = properMap
        terms = termMap
        termZH = zhMap
        project = projectMap
        ready = true
        lock.unlock()
        ReasoningDiagnostics.log(
            "ExternalLexicon proper=\(properMap.count) terms=\(termMap.count) zh=\(zhMap.count) project=\(projectMap.count)"
        )
    }

    /// Drop the in-memory cache so the next `ensureLoaded` re-reads disk + shared corrections.
    public func invalidate() {
        lock.lock()
        ready = false
        proper = [:]
        terms = [:]
        termZH = [:]
        project = [:]
        lock.unlock()
    }

    public func loadSynchronously(
        properURL: URL?,
        termsURL: URL?,
        zhURL: URL?,
        projectURL: URL? = nil,
        includeSharedCorrections: Bool = true
    ) {
        lock.lock()
        var properMap = properURL.flatMap { Self.parseTSV(url: $0) } ?? [:]
        var termMap = termsURL.flatMap { Self.parseTSV(url: $0) } ?? [:]
        termZH = zhURL.flatMap { Self.parseTSV(url: $0) } ?? [:]
        var projectMap = projectURL.flatMap { Self.parseTSV(url: $0) } ?? [:]
        if includeSharedCorrections {
            if projectMap.isEmpty {
                projectMap = Self.loadProjectTSV()
            }
            Self.mergeSharedCorrections(proper: &properMap, terms: &termMap, project: &projectMap)
        } else if projectMap.isEmpty, let projectURL {
            projectMap = Self.parseTSV(url: projectURL) ?? [:]
        }
        proper = properMap
        terms = termMap
        project = projectMap
        ready = true
        lock.unlock()
    }

    public func properNoun(code: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return proper[code] ?? project[code]
    }

    public func techTerm(code: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return terms[code] ?? project[code]
    }

    public func chineseGloss(for displayOrCode: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = termZH[displayOrCode] { return hit }
        let compact = displayOrCode.lowercased().filter { $0.isASCII && $0.isLetter }
        return termZH.first(where: {
            $0.key.lowercased().filter { $0.isASCII && $0.isLetter } == compact
        })?.value
    }

    public func allProperCodes() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(Set(proper.keys).union(project.keys))
    }

    public func allTermCodes() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(Set(terms.keys).union(project.keys))
    }

    public static func projectLexiconURL() -> URL {
        // Prefer the shared corrections file; keep the legacy path for readers.
        SharedCorrectionLexicon.shared.storageURL
    }

    public static func legacyProjectLexiconURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeVoiceOSS/Lexicon/project.tsv", isDirectory: false)
    }

    private static func loadProjectTSV() -> [String: String] {
        // Shared corrections first; fall back to legacy project.tsv via migration helper.
        let shared = SharedCorrectionLexicon.shared.pinyinCodeMap()
        if !shared.isEmpty { return shared }
        return parseTSV(url: legacyProjectLexiconURL()) ?? [:]
    }

    private static func mergeSharedCorrections(
        proper: inout [String: String],
        terms: inout [String: String],
        project: inout [String: String]
    ) {
        let lexicon = SharedCorrectionLexicon.shared
        lexicon.reload()
        for entry in lexicon.allEntries() {
            guard !entry.pinyinCode.isEmpty else { continue }
            // Never clobber bundled proper/tech tables — shared rows fill gaps
            // and remain available via the project fallback map.
            project[entry.pinyinCode] = entry.canonical
            switch entry.kind {
            case .proper where proper[entry.pinyinCode] == nil:
                proper[entry.pinyinCode] = entry.canonical
            case .term where terms[entry.pinyinCode] == nil:
                terms[entry.pinyinCode] = entry.canonical
            default:
                break
            }
        }
    }

    private static func loadTSV(named: String, subdirectory: String, bundle: Bundle) -> [String: String] {
        let url = bundle.url(forResource: named, withExtension: "tsv", subdirectory: subdirectory)
            ?? bundle.url(forResource: named, withExtension: "tsv")
        return url.flatMap { parseTSV(url: $0) } ?? [:]
    }

    static func parseTSV(url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parseTSV(text: text)
    }

    static func parseTSV(text: String) -> [String: String] {
        var map: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let code = String(parts[0]).lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let display = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty, !display.isEmpty else { continue }
            map[code] = display
        }
        return map
    }
}

/// Multi-path lattice over pinyin words + protected English / proper nouns.
public enum MixedTokenAnalyzer {
    /// High-frequency keyboard / UI / coding tokens that should carve out of
    /// pinyin even when the shipped TSV is thin. Kept short on purpose — longer
    /// product names belong in `tech-terms.tsv` / `proper-nouns.tsv`.
    static let builtinEnglishTerms: [(code: String, display: String)] = [
        ("tab", "tab"),
        ("shift", "Shift"),
        ("enter", "Enter"),
        ("return", "Return"),
        ("escape", "Esc"),
        ("esc", "Esc"),
        ("delete", "Delete"),
        ("option", "Option"),
        ("command", "Command"),
        ("control", "Control"),
        ("ctrl", "Ctrl"),
        ("alt", "Alt"),
        ("space", "Space"),
        ("click", "click"),
        ("scroll", "scroll"),
        ("focus", "focus"),
        ("hover", "hover"),
        ("debug", "debug"),
        ("build", "build"),
        ("commit", "commit"),
        ("branch", "branch"),
        ("merge", "merge"),
        ("rebase", "rebase"),
        ("stash", "stash"),
        ("docker", "Docker"),
        ("linux", "Linux"),
        ("macos", "macOS"),
        ("swift", "Swift"),
        ("python", "Python"),
        ("rust", "Rust"),
        ("kotlin", "Kotlin"),
        ("typescript", "TypeScript"),
        ("javascript", "JavaScript"),
    ]

    public static func compose(
        rawInput: String,
        documentContext: String = "",
        style: MixedOutputStyle = .developer,
        lexicon: PinyinLexicon = .shared,
        external: ExternalLexicon = .shared,
        maxLetters: Int = 80
    ) -> MixedComposition? {
        guard lexicon.prepareForUse() else {
            ReasoningDiagnostics.log("compose skipped: pinyin lexicon not ready raw=\(rawInput)")
            return nil
        }
        external.ensureLoaded()
        let latin = PinyinTypoCorrector.latinCode(from: rawInput)
        guard latin.count >= 4, latin.count <= maxLetters else {
            ReasoningDiagnostics.log("compose skipped: latin length \(latin.count) raw=\(rawInput)")
            return nil
        }

        if let mixed = composeMixed(
            latin: latin,
            documentContext: documentContext,
            style: style,
            lexicon: lexicon,
            external: external
        ) {
            ReasoningDiagnostics.log("compose mixed → \(mixed.text)")
            return mixed
        }

        // Pure pinyin path.
        guard let phrase = PhraseComposer.compose(
            rawInput: latin,
            documentContext: documentContext,
            lexicon: lexicon
        ) else {
            ReasoningDiagnostics.log("compose nil (no mixed, no phrase) latin=\(latin)")
            return nil
        }
        let token = MixedToken(
            kind: .pinyinWord,
            code: latin,
            display: phrase.text,
            weight: phrase.score
        )
        ReasoningDiagnostics.log(
            "compose phrase → \(phrase.text) fuzzy=\(phrase.fuzzyEdits) conf=\(phrase.confidence)"
        )
        return MixedComposition(
            text: phrase.text,
            tokens: [token],
            score: phrase.score,
            confidence: phrase.confidence,
            hasProperNoun: false,
            hasEnglish: false,
            fuzzyEdits: phrase.fuzzyEdits
        )
    }

    /// Render tokens according to output style.
    public static func render(_ tokens: [MixedToken], style: MixedOutputStyle, external: ExternalLexicon) -> String {
        tokens.map { token in
            switch (style, token.kind) {
            case (.developer, _), (.original, _):
                return token.display
            case (.smartChinese, .properNoun):
                return token.display  // brands stay English
            case (.smartChinese, .englishTerm):
                return external.chineseGloss(for: token.display) ?? token.display
            case (.smartChinese, .pinyinWord):
                return token.display
            }
        }.joined()
    }

    // MARK: - Mixed lattice

    private static func composeMixed(
        latin: String,
        documentContext: String,
        style: MixedOutputStyle,
        lexicon: PinyinLexicon,
        external: ExternalLexicon
    ) -> MixedComposition? {
        let chars = Array(latin)
        let n = chars.count

        // 1) Greedy longest proper-noun / tech-term matches (non-overlapping).
        struct Span {
            let start: Int
            let end: Int
            let token: MixedToken
        }
        var reserved: [Span] = []
        var cursor = 0
        let nounCodes = external.allProperCodes().sorted { $0.count > $1.count }
        let termCodes = mergedEnglishCodes(external: external)
        while cursor < n {
            let suffix = String(chars[cursor...])
            var matched: Span?
            for code in nounCodes where suffix.hasPrefix(code) {
                guard let display = external.properNoun(code: code) else { continue }
                matched = Span(
                    start: cursor,
                    end: cursor + code.count,
                    token: MixedToken(kind: .properNoun, code: code, display: display, weight: 100)
                )
                break
            }
            if matched == nil {
                for entry in termCodes where suffix.hasPrefix(entry.code) {
                    let code = entry.code
                    let span = String(chars[cursor..<cursor + code.count])
                    let pinyinLegal = PinyinTypoCorrector.canSegment(span, allowTrailingPrefix: false)
                    // Skip short pinyin-legal tokens unless they sit as a clear
                    // English island between segmentable Chinese gaps (or trail
                    // a Chinese prefix). Avoids carving "you"/"ban" out of pure
                    // pinyin while still allowing "…yongtablai…".
                    if pinyinLegal, code.count <= 6,
                       !isClearEnglishIsland(chars: chars, start: cursor, length: code.count) {
                        continue
                    }
                    matched = Span(
                        start: cursor,
                        end: cursor + code.count,
                        token: MixedToken(kind: .englishTerm, code: code, display: entry.display, weight: 80)
                    )
                    break
                }
            }
            if let matched {
                reserved.append(matched)
                cursor = matched.end
            } else {
                cursor += 1
            }
        }
        guard !reserved.isEmpty else { return nil }

        // 2) Compose each pinyin gap independently, then interleave with reserved spans.
        var tokens: [MixedToken] = []
        var score = 0.0
        var gapStart = 0
        for span in reserved {
            if gapStart < span.start {
                let gap = String(chars[gapStart..<span.start])
                if let phrase = PhraseComposer.compose(
                    rawInput: gap,
                    documentContext: gapStart == 0 ? documentContext : "",
                    lexicon: lexicon
                ) {
                    tokens.append(MixedToken(
                        kind: .pinyinWord,
                        code: gap,
                        display: phrase.text,
                        weight: phrase.score
                    ))
                    score += phrase.score
                } else if let syllables = PhraseComposer.segmentSyllables(gap) {
                    // Fallback: best single entries per syllable.
                    var piece = ""
                    for syl in syllables {
                        if let entry = lexicon.bestEntry(forCompactCode: syl) {
                            piece += entry.text
                        } else {
                            return nil
                        }
                    }
                    tokens.append(MixedToken(kind: .pinyinWord, code: gap, display: piece, weight: 1))
                } else if !gap.isEmpty {
                    return nil
                }
            }
            tokens.append(span.token)
            score += 12.0 + Double(span.token.code.count)
            gapStart = span.end
        }
        if gapStart < n {
            let gap = String(chars[gapStart..<n])
            if let phrase = PhraseComposer.compose(
                rawInput: gap,
                documentContext: "",
                lexicon: lexicon
            ) {
                tokens.append(MixedToken(
                    kind: .pinyinWord,
                    code: gap,
                    display: phrase.text,
                    weight: phrase.score
                ))
                score += phrase.score
            } else if let syllables = PhraseComposer.segmentSyllables(gap) {
                var piece = ""
                for syl in syllables {
                    if let entry = lexicon.bestEntry(forCompactCode: syl) {
                        piece += entry.text
                    } else {
                        return nil
                    }
                }
                tokens.append(MixedToken(kind: .pinyinWord, code: gap, display: piece, weight: 1))
            } else if !gap.isEmpty {
                return nil
            }
        }

        guard tokens.contains(where: { $0.kind == .properNoun || $0.kind == .englishTerm }) else {
            return nil
        }
        let text = spaceMixed(render(tokens, style: style, external: external))
        let hasProper = tokens.contains { $0.kind == .properNoun }
        let hasEnglish = tokens.contains { $0.kind == .englishTerm }
        return MixedComposition(
            text: text,
            tokens: tokens,
            score: score,
            confidence: hasProper ? .high : .medium,
            hasProperNoun: hasProper,
            hasEnglish: hasEnglish
        )
    }

    /// External TSV terms plus builtins, longest-first. External display wins on
    /// code collisions so project lexicons can override casing.
    private static func mergedEnglishCodes(
        external: ExternalLexicon
    ) -> [(code: String, display: String)] {
        var map: [String: String] = [:]
        for entry in builtinEnglishTerms {
            map[entry.code] = entry.display
        }
        for code in external.allTermCodes() {
            if let display = external.techTerm(code: code) {
                map[code] = display
            }
        }
        return map.map { (code: $0.key, display: $0.value) }.sorted { $0.code.count > $1.code.count }
    }

    /// True when `chars[start..<start+length]` is flanked by segmentable pinyin
    /// (or sits after a Chinese prefix at end-of-input). That pattern is an
    /// intentional English insert, not a false carve-out of pure pinyin.
    private static func isClearEnglishIsland(chars: [Character], start: Int, length: Int) -> Bool {
        let n = chars.count
        let end = start + length
        guard start >= 0, end <= n, length > 0 else { return false }
        let left = start == 0 ? "" : String(chars[0..<start])
        let right = end == n ? "" : String(chars[end..<n])
        let leftOK = left.isEmpty
            || PinyinTypoCorrector.canSegment(left, allowTrailingPrefix: false)
        let rightOK = right.isEmpty
            || PinyinTypoCorrector.canSegment(right, allowTrailingPrefix: true)
        guard leftOK, rightOK else { return false }
        // Require a Chinese side so bare "you" / "ban" never win alone.
        return !left.isEmpty || !right.isEmpty
    }

    private static func continuationBonus(word: String, context: String) -> Double {
        let suffixes = ["有没有改", "改", "删", "删除", "写", "要", "做"]
        let preferred: Set<String> = ["移除", "删除", "修改", "更改", "替换", "更新"]
        let demoted: Set<String> = ["一处", "一出", "一", "溢出", "益处"]
        let wants = suffixes.contains { context.hasSuffix($0) }
        guard wants else { return 0 }
        if preferred.contains(word) { return 20 }
        if demoted.contains(word) { return -12 }
        return 0
    }

    private static func spaceMixed(_ text: String) -> String {
        var result = ""
        var previousWasASCIILetter = false
        for character in text {
            let isASCIILetter = character.isASCII && character.isLetter
            let isCJK = character.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            if isCJK, previousWasASCIILetter {
                result.append(" ")
            }
            if isASCIILetter, let last = result.last,
               last.unicodeScalars.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
                result.append(" ")
            }
            result.append(character)
            previousWasASCIILetter = isASCIILetter
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
