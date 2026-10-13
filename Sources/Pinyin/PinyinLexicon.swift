import Foundation
import VibeVoiceShared

/// Entry from `pinyin_simp.dict.yaml`: text + frequency weight.
public struct PinyinLexiconEntry: Equatable, Sendable {
    public let text: String
    public let weight: Int

    public init(text: String, weight: Int) {
        self.text = text
        self.weight = weight
    }
}

/// Read-only index of Rime `pinyin_simp` keyed by compacted (space-free) pinyin.
/// Built asynchronously so the IME stays responsive on first launch; callers
/// treat an unfinished index as a no-op and fall back to Rime alone.
public final class PinyinLexicon: @unchecked Sendable {
    public static let shared = PinyinLexicon()

    private let lock = NSLock()
    private var index: [String: [PinyinLexiconEntry]] = [:]
    private var ready = false
    private var loading = false

    public var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return ready
    }

    /// Kick off background parse if needed. Safe to call repeatedly.
    public func ensureLoaded(bundle: Bundle = .main) {
        lock.lock()
        if ready || loading {
            lock.unlock()
            return
        }
        loading = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.loadFromBundle(bundle)
        }
    }

    /// Block until the index is ready (or failed). Call on the first keystroke
    /// path so mixed reasoning never silently no-ops while the async parse is
    /// still in flight.
    @discardableResult
    public func prepareForUse(bundle: Bundle = .main, timeoutSeconds: TimeInterval = 8) -> Bool {
        if isReady { return true }
        ensureLoaded(bundle: bundle)
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if isReady { return true }
            // Still loading on the utility queue — yield briefly.
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Last resort: parse on the caller thread so a hung queue cannot
        // permanently disable reasoning.
        lock.lock()
        let already = ready
        let inFlight = loading
        lock.unlock()
        if already { return true }
        if !inFlight {
            loadFromBundle(bundle)
        } else {
            // Wait a bit more for the in-flight job.
            let extra = Date().addingTimeInterval(4)
            while Date() < extra {
                if isReady { return true }
                Thread.sleep(forTimeInterval: 0.05)
            }
            if !isReady {
                loadFromBundle(bundle)
            }
        }
        return isReady
    }

    private func loadFromBundle(_ bundle: Bundle) {
        let url = Self.dictionaryURL(bundle: bundle)
            ?? Bundle.main.resourceURL?
                .appendingPathComponent("RimeData/pinyin_simp.dict.yaml")
        var built = url.flatMap { Self.parse(url: $0) } ?? [:]
        Self.mergePhraseOverlay(&built, bundle: bundle)
        Self.mergeSharedCorrectionOverlay(&built)
        lock.lock()
        index = built
        ready = !built.isEmpty
        loading = false
        lock.unlock()
        ReasoningDiagnostics.log(
            "PinyinLexicon ready=\(ready) entries=\(built.count) url=\(url?.path ?? "nil")"
        )
    }

    /// Synchronous load for tests / tooling.
    public func loadSynchronously(
        from url: URL,
        phraseOverlayURL: URL? = nil,
        includeSharedCorrections: Bool = true
    ) {
        var built = Self.parse(url: url) ?? [:]
        if let phraseOverlayURL {
            Self.mergePhraseOverlay(&built, url: phraseOverlayURL)
        } else {
            // Repo: Resources/InputMethod/{RimeData,Lexicon}
            // Bundle: Contents/Resources/{RimeData,Lexicon}
            // `url` points at a file inside RimeData, so climb to the parent of
            // RimeData (where Lexicon sits as a sibling).
            let defaultOverlay = url
                .deletingLastPathComponent() // filename → RimeData/
                .deletingLastPathComponent() // → Resources[/InputMethod]/
                .appendingPathComponent("Lexicon/common-phrases.tsv")
            Self.mergePhraseOverlay(&built, url: defaultOverlay)
        }
        if includeSharedCorrections {
            Self.mergeSharedCorrectionOverlay(&built)
        }
        lock.lock()
        index = built
        ready = !built.isEmpty
        loading = false
        lock.unlock()
    }

    public func entries(forCompactCode code: String) -> [PinyinLexiconEntry] {
        lock.lock(); defer { lock.unlock() }
        return index[code] ?? []
    }

    public func bestEntry(forCompactCode code: String) -> PinyinLexiconEntry? {
        entries(forCompactCode: code).max(by: { $0.weight < $1.weight })
    }

    public static func dictionaryURL(bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(
            forResource: "pinyin_simp",
            withExtension: "dict.yaml",
            subdirectory: "RimeData"
        ) { return url }
        if let url = bundle.url(forResource: "pinyin_simp", withExtension: "dict.yaml") {
            return url
        }
        // Repo / test layout: walk up from #filePath is handled by callers.
        return nil
    }

    /// Compact a spaced Rime code (`yi chu`) to a continuous key (`yichu`).
    public static func compactCode(_ spaced: String) -> String {
        spaced.lowercased().filter { $0.isASCII && $0.isLetter }
    }

    // MARK: - Parsing

    static func parse(url: URL) -> [String: [PinyinLexiconEntry]]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text: text)
    }

    static func parse(text: String) -> [String: [PinyinLexiconEntry]] {
        var result: [String: [PinyinLexiconEntry]] = [:]
        var pastHeader = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "..." {
                pastHeader = true
                continue
            }
            guard pastHeader, !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let word = String(parts[0])
            let codeSpaced = String(parts[1])
            let weight = parts.count >= 3 ? Int(parts[2]) ?? 0 : 0
            let compact = compactCode(codeSpaced)
            guard !compact.isEmpty, !word.isEmpty else { continue }
            // Keep multi-syllable entries (space in original code) and single
            // characters used as Viterbi fallbacks.
            let isMulti = codeSpaced.contains(" ")
            let isSingleChar = word.count == 1
            guard isMulti || isSingleChar else { continue }
            if isSingleChar, weight < 50 { continue }
            result[compact, default: []].append(PinyinLexiconEntry(text: word, weight: weight))
        }
        for key in result.keys {
            result[key]?.sort { $0.weight > $1.weight }
        }
        return result
    }

    /// Overlay `common-phrases.tsv` (code\\ttext\\tweight) so compounds missing
    /// from pinyin_simp still win over high-frequency single characters.
    static func mergePhraseOverlay(
        _ index: inout [String: [PinyinLexiconEntry]],
        bundle: Bundle
    ) {
        let url = bundle.url(forResource: "common-phrases", withExtension: "tsv", subdirectory: "Lexicon")
            ?? bundle.url(forResource: "common-phrases", withExtension: "tsv")
        guard let url else { return }
        mergePhraseOverlay(&index, url: url)
    }

    static func mergePhraseOverlay(
        _ index: inout [String: [PinyinLexiconEntry]],
        url: URL
    ) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }
        var added = 0
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let code = String(parts[0]).lowercased().filter { $0.isASCII && $0.isLetter }
            let word = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let weight = parts.count >= 3 ? Int(parts[2]) ?? 8_000 : 8_000
            guard !code.isEmpty, !word.isEmpty else { continue }
            var list = index[code] ?? []
            if let existing = list.firstIndex(where: { $0.text == word }) {
                if weight > list[existing].weight {
                    list[existing] = PinyinLexiconEntry(text: word, weight: weight)
                }
            } else {
                list.append(PinyinLexiconEntry(text: word, weight: weight))
            }
            list.sort { $0.weight > $1.weight }
            index[code] = list
            added += 1
        }
        if added > 0 {
            ReasoningDiagnostics.log("PinyinLexicon phrase overlay +\(added) from \(url.lastPathComponent)")
        }
    }

    /// Merge user/project shared corrections (includes `source` provenance on disk).
    static func mergeSharedCorrectionOverlay(_ index: inout [String: [PinyinLexiconEntry]]) {
        let rows = SharedCorrectionLexicon.shared.pinyinPhraseOverlay()
        guard !rows.isEmpty else { return }
        var added = 0
        for row in rows {
            var list = index[row.code] ?? []
            if let existing = list.firstIndex(where: { $0.text == row.text }) {
                if row.weight > list[existing].weight {
                    list[existing] = PinyinLexiconEntry(text: row.text, weight: row.weight)
                }
            } else {
                list.append(PinyinLexiconEntry(text: row.text, weight: row.weight))
                added += 1
            }
            list.sort { $0.weight > $1.weight }
            index[row.code] = list
        }
        if added > 0 {
            ReasoningDiagnostics.log("PinyinLexicon shared-corrections overlay +\(added)")
        }
    }
}
