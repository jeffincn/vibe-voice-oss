import Foundation

/// Where a shared correction entry came from. Stored in the TSV `source` column
/// so Settings / tooling can explain provenance and importers can merge safely.
public enum SharedCorrectionSource: String, Sendable, Codable, CaseIterable {
    /// Scanned from a local git working tree (class / function / branch names).
    case project
    /// Lifted once from the legacy `project.tsv` file.
    case migrated
    /// Hand-edited or otherwise user-authored rows.
    case user
    /// Unknown / forward-compatible fallback.
    case other

    public init(raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = SharedCorrectionSource(rawValue: key) ?? .other
    }

    public var displayNameZH: String {
        switch self {
        case .project: return "项目导入"
        case .migrated: return "旧词表迁移"
        case .user: return "用户"
        case .other: return "其他"
        }
    }
}

public enum SharedCorrectionKind: String, Sendable, Codable, CaseIterable {
    case phrase
    case proper
    case term

    public init(raw: String) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self = SharedCorrectionKind(rawValue: key) ?? .phrase
    }

    public var defaultWeight: Int {
        switch self {
        case .phrase: return 8_000
        case .proper: return 100
        case .term: return 80
        }
    }
}

public struct SharedCorrectionEntry: Equatable, Sendable, Codable {
    public var canonical: String
    public var pinyinCode: String
    public var aliases: [String]
    public var kind: SharedCorrectionKind
    public var weight: Int
    /// Provenance: `project` / `migrated` / `user` / …
    public var source: SharedCorrectionSource

    public init(
        canonical: String,
        pinyinCode: String = "",
        aliases: [String] = [],
        kind: SharedCorrectionKind = .phrase,
        weight: Int? = nil,
        source: SharedCorrectionSource = .user
    ) {
        self.canonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pinyinCode = pinyinCode.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        self.aliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.kind = kind
        self.weight = weight ?? kind.defaultWeight
        self.source = source
    }
}

/// Cross-product correction lexicon shared by Voice (ASR / LLM) and the IMK pinyin engine.
///
/// File: `~/Library/Application Support/VibeVoiceOSS/Lexicon/shared-corrections.v1.tsv`
///
/// ```
/// # canonical	pinyin_code	aliases	kind	weight	source
/// 魔法棒	mofabang	魔法帮|魔发棒	phrase	12000	user
/// Core ML	coreml	扣肉ML|core ml	proper	100	project
/// ```
public final class SharedCorrectionLexicon: @unchecked Sendable {
    public static let shared = SharedCorrectionLexicon()
    public static let fileName = "shared-corrections.v1.tsv"
    public static let header =
        "# canonical\tpinyin_code\taliases\tkind\tweight\tsource"

    private let lock = NSLock()
    private var entries: [SharedCorrectionEntry] = []
    private var loaded = false
    private let fileURL: URL
    private let legacyProjectURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeVoiceOSS/Lexicon", isDirectory: true)
        self.fileURL = base.appendingPathComponent(Self.fileName, isDirectory: false)
        self.legacyProjectURL = base.appendingPathComponent("project.tsv", isDirectory: false)
    }

    public var storageURL: URL { fileURL }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        return entries.count
    }

    public func allEntries() -> [SharedCorrectionEntry] {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        return entries
    }

    /// Force reload from disk (e.g. after an importer writes a new file).
    public func reload() {
        lock.lock(); defer { lock.unlock() }
        loaded = false
        ensureLoadedLocked()
    }

    // MARK: - Voice helpers

    /// Canonical terms for ASR hotspot biasing (capped, longest / heaviest first).
    public func canonicalTerms(limit: Int = 80) -> [String] {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        var seen = Set<String>()
        var result: [String] = []
        let ranked = entries.sorted {
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.canonical.count > $1.canonical.count
        }
        for entry in ranked {
            let term = entry.canonical
            guard !term.isEmpty, seen.insert(term).inserted else { continue }
            result.append(term)
            if result.count >= limit { break }
        }
        return result
    }

    /// LLM-facing correction block. Prefers rows that carry aliases; fills with
    /// high-weight proper/term names so the model still sees project vocabulary.
    public func correctionPromptBlock(limit: Int = 60) -> String {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        var lines: [String] = []
        var seen = Set<String>()

        let withAliases = entries.filter { !$0.aliases.isEmpty }
            .sorted { $0.weight > $1.weight }
        for entry in withAliases {
            let key = entry.canonical.lowercased()
            guard seen.insert(key).inserted else { continue }
            let aliasText = entry.aliases.joined(separator: " / ")
            lines.append("- \(aliasText) → \(entry.canonical)（来源：\(entry.source.displayNameZH)）")
            if lines.count >= limit { break }
        }

        if lines.count < limit {
            let fillers = entries.filter {
                $0.aliases.isEmpty && ($0.kind == .proper || $0.kind == .term || $0.weight >= 8_000)
            }
            .sorted { $0.weight > $1.weight }
            for entry in fillers {
                let key = entry.canonical.lowercased()
                guard seen.insert(key).inserted else { continue }
                lines.append("- \(entry.canonical)（来源：\(entry.source.displayNameZH)）")
                if lines.count >= limit { break }
            }
        }

        guard !lines.isEmpty else { return "" }
        return """
        共享纠正词表（来自拼音/项目词库；出现别名或明显同音误辨时改为标准词，勿编造表外名称）：
        \(lines.joined(separator: "\n"))
        """
    }

    /// Merge shared canonical terms into an existing ASR hotspot prompt.
    public static func mergingASRPrompt(_ base: String, terms: [String], maxChars: Int = 900) -> String {
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !terms.isEmpty else { return trimmedBase }
        var parts: [String] = []
        var seen = Set<String>()
        for token in trimmedBase.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" || $0 == ";" }) {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            parts.append(t)
        }
        for term in terms {
            let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            parts.append(t)
        }
        var result = parts.joined(separator: ", ")
        if result.count > maxChars {
            // Keep as many whole terms as fit.
            var kept: [String] = []
            var length = 0
            for part in parts {
                let next = kept.isEmpty ? part.count : length + 2 + part.count
                if next > maxChars { break }
                kept.append(part)
                length = next
            }
            result = kept.joined(separator: ", ")
        }
        return result
    }

    public static func appendingCorrectionContext(to roleContext: String, block: String) -> String {
        let role = roleContext.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = block.trimmingCharacters(in: .whitespacesAndNewlines)
        if role.isEmpty { return correction }
        if correction.isEmpty { return role }
        return role + "\n\n" + correction
    }

    // MARK: - Pinyin helpers

    /// Rows usable as ExternalLexicon proper/term overlays (`code → display`).
    public func pinyinCodeMap(kinds: Set<SharedCorrectionKind> = [.proper, .term, .phrase]) -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        var map: [String: String] = [:]
        for entry in entries where kinds.contains(entry.kind) {
            guard !entry.pinyinCode.isEmpty else { continue }
            map[entry.pinyinCode] = entry.canonical
        }
        return map
    }

    /// Phrase overlays for `PinyinLexicon` (`code → (text, weight)`).
    public func pinyinPhraseOverlay() -> [(code: String, text: String, weight: Int)] {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        return entries.compactMap { entry in
            guard !entry.pinyinCode.isEmpty, !entry.canonical.isEmpty else { return nil }
            return (entry.pinyinCode, entry.canonical, entry.weight)
        }
    }

    // MARK: - Persistence

    @discardableResult
    public func replaceAll(_ newEntries: [SharedCorrectionEntry]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        entries = Self.deduplicated(newEntries)
        loaded = true
        return writeLocked()
    }

    /// Upsert by `(pinyinCode, canonical)` when code is present, else by canonical.
    @discardableResult
    public func upsert(_ incoming: [SharedCorrectionEntry]) -> Int {
        lock.lock(); defer { lock.unlock() }
        ensureLoadedLocked()
        var map = Dictionary(uniqueKeysWithValues: entries.map { (Self.dedupeKey($0), $0) })
        var added = 0
        for entry in incoming {
            let key = Self.dedupeKey(entry)
            if map[key] == nil { added += 1 }
            map[key] = entry
        }
        entries = Array(map.values).sorted {
            if $0.pinyinCode != $1.pinyinCode { return $0.pinyinCode < $1.pinyinCode }
            return $0.canonical < $1.canonical
        }
        _ = writeLocked()
        return added
    }

    public static func parse(text: String) -> [SharedCorrectionEntry] {
        var result: [SharedCorrectionEntry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count >= 1 else { continue }
            let canonical = parts[0].trimmingCharacters(in: .whitespaces)
            guard !canonical.isEmpty else { continue }
            let code = parts.count > 1 ? parts[1] : ""
            let aliasesRaw = parts.count > 2 ? parts[2] : ""
            let kind = SharedCorrectionKind(raw: parts.count > 3 ? parts[3] : "phrase")
            let weight = parts.count > 4 ? Int(parts[4]) : nil
            let source = SharedCorrectionSource(raw: parts.count > 5 ? parts[5] : "user")
            let aliases = aliasesRaw
                .split(separator: "|", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            result.append(SharedCorrectionEntry(
                canonical: canonical,
                pinyinCode: code,
                aliases: aliases,
                kind: kind,
                weight: weight,
                source: source
            ))
        }
        return deduplicated(result)
    }

    public static func serialize(_ entries: [SharedCorrectionEntry]) -> String {
        var lines = [header]
        for entry in entries.sorted(by: {
            if $0.pinyinCode != $1.pinyinCode { return $0.pinyinCode < $1.pinyinCode }
            return $0.canonical < $1.canonical
        }) {
            let aliases = entry.aliases.joined(separator: "|")
            lines.append([
                entry.canonical,
                entry.pinyinCode,
                aliases,
                entry.kind.rawValue,
                String(entry.weight),
                entry.source.rawValue,
            ].joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Convert legacy `code\\tdisplay[\\tkind]` project.tsv rows.
    public static func entriesFromLegacyProjectTSV(_ text: String) -> [SharedCorrectionEntry] {
        var result: [SharedCorrectionEntry] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { continue }
            let code = String(parts[0])
            let display = String(parts[1]).trimmingCharacters(in: .whitespaces)
            guard !display.isEmpty else { continue }
            let kindRaw = parts.count >= 3 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : "project"
            let kind: SharedCorrectionKind
            switch kindRaw.lowercased() {
            case "proper": kind = .proper
            case "term", "tech": kind = .term
            case "project": kind = .proper
            default: kind = .proper
            }
            result.append(SharedCorrectionEntry(
                canonical: display,
                pinyinCode: code,
                aliases: [],
                kind: kind,
                weight: kind.defaultWeight,
                source: .migrated
            ))
        }
        return result
    }

    // MARK: - Private

    private func ensureLoadedLocked() {
        if loaded { return }
        loaded = true
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let text = String(data: data, encoding: .utf8) {
            entries = Self.parse(text: text)
            return
        }
        // One-shot migration from legacy project.tsv.
        if let data = try? Data(contentsOf: legacyProjectURL),
           let text = String(data: data, encoding: .utf8) {
            entries = Self.entriesFromLegacyProjectTSV(text)
            _ = writeLocked()
            return
        }
        entries = []
    }

    private func writeLocked() -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let payload = Self.serialize(entries)
            let tmp = fileURL.appendingPathExtension("tmp")
            try payload.write(to: tmp, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(
                fileURL, withItemAt: tmp, backupItemName: nil, options: .usingNewMetadataOnly
            )
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            do {
                try Self.serialize(entries).write(to: fileURL, atomically: true, encoding: .utf8)
                return true
            } catch {
                return false
            }
        }
    }

    private static func dedupeKey(_ entry: SharedCorrectionEntry) -> String {
        if entry.pinyinCode.isEmpty {
            return "c:\(entry.canonical.lowercased())"
        }
        return "p:\(entry.pinyinCode)|\(entry.canonical.lowercased())"
    }

    private static func deduplicated(_ entries: [SharedCorrectionEntry]) -> [SharedCorrectionEntry] {
        var map: [String: SharedCorrectionEntry] = [:]
        for entry in entries {
            map[dedupeKey(entry)] = entry
        }
        return Array(map.values).sorted {
            if $0.pinyinCode != $1.pinyinCode { return $0.pinyinCode < $1.pinyinCode }
            return $0.canonical < $1.canonical
        }
    }
}
