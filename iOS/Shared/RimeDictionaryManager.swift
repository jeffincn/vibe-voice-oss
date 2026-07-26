import Foundation

/// Imports user-owned Rime dictionaries without writing into the signed app
/// bundle. The accepted format is the normal Rime TSV body (`word<TAB>pinyin`
/// with an optional frequency), which covers THUOCL-derived and hand-authored
/// lists after they have been annotated with pronunciation.
enum RimeDictionaryManager {
    struct ImportResult: Sendable {
        let entries: Int
        let fileName: String
    }

    static func importDictionary(from url: URL) throws -> ImportResult {
        guard url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        defer { url.stopAccessingSecurityScopedResource() }
        let text = try String(contentsOf: url, encoding: .utf8)
        let entries = text.split(whereSeparator: \.isNewline).compactMap(parse).filter { !$0.word.isEmpty }
        guard !entries.isEmpty else { throw ImportError.noEntries }
        // Rime searches the user data directory for <user_dict>.dict.yaml.
        // Keeping the file alongside the deployment lets both the app and
        // extension consume it without touching the signed resource bundle.
        let directory = try RimeEngineFactory.containerDirectory(named: "Deploy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("user.dict.yaml")
        var output = "# Imported by Vibe Voice OSS; user-owned data\n---\nname: vibe_user\nversion: \"0.7.0\"\nsort: by_weight\n...\n"
        output += entries.map { "\($0.word)\t\($0.spelling)\t\($0.weight)" }.joined(separator: "\n")
        try output.data(using: .utf8)?.write(to: destination, options: .atomic)
        return ImportResult(entries: entries.count, fileName: url.lastPathComponent)
    }

    enum ImportError: LocalizedError {
        case noEntries
        var errorDescription: String? { "没有找到可用的 Rime 词条。请使用“词<TAB>拼音<TAB>词频”格式。" }
    }

    private struct Entry {
        let word: String
        let spelling: String
        let weight: Int
    }

    private static func parse(_ line: Substring) -> Entry? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("#"), value != "..." else { return nil }
        let fields = value.split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { return nil }
        let word = String(fields[0]).trimmingCharacters(in: .whitespaces)
        let spelling = String(fields[1]).trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !spelling.isEmpty, spelling.allSatisfy({ $0.isLetter || $0 == "'" || $0 == " " }) else { return nil }
        return Entry(word: word, spelling: spelling, weight: fields.dropFirst(2).first.flatMap { Int($0) } ?? 100)
    }
}
