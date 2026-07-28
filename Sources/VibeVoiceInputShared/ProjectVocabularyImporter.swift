import Foundation

/// Extracts CamelCase / snake_case symbols from a git working tree and writes
/// them into the user-level project lexicon consumed by `ExternalLexicon`.
public enum ProjectVocabularyImporter {
    public static func defaultOutputURL() -> URL {
        ExternalLexicon.projectLexiconURL()
    }

    /// Scan `root` for Swift/TS/Python-ish identifiers and product-looking names.
    @discardableResult
    public static func importFromRepository(at root: URL, output: URL? = nil) -> Int {
        let out = output ?? defaultOutputURL()
        var map: [String: String] = [:]

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let allowedExt: Set<String> = ["swift", "ts", "tsx", "js", "py", "go", "rs", "md"]
        let skipDirs: Set<String> = [
            ".build", "node_modules", "dist", "Vendor", "Pods", ".git",
            "DerivedData", "xcuserdata",
        ]

        while let item = enumerator.nextObject() as? URL {
            if item.hasDirectoryPath {
                if skipDirs.contains(item.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard allowedExt.contains(item.pathExtension.lowercased()) else { continue }
            guard let text = try? String(contentsOf: item, encoding: .utf8) else { continue }
            for symbol in extractSymbols(from: text) {
                let code = compact(symbol)
                guard code.count >= 4 else { continue }
                map[code] = symbol
            }
            // File stem as a product-ish token (VibeVoiceOSS → vibevoiceoss).
            let stem = item.deletingPathExtension().lastPathComponent
            let stemCode = compact(stem)
            if stemCode.count >= 4 {
                map[stemCode] = stem
            }
        }

        // Branch names from `git branch` when available.
        if let branches = gitBranches(in: root) {
            for branch in branches {
                let leaf = branch.split(separator: "/").last.map(String.init) ?? branch
                let code = compact(leaf)
                if code.count >= 4 {
                    map[code] = leaf
                }
            }
        }

        guard !map.isEmpty else { return 0 }
        let dir = out.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines = ["# code\tdisplay\tkind  (auto-generated project vocabulary)"]
        for (code, display) in map.sorted(by: { $0.key < $1.key }) {
            lines.append("\(code)\t\(display)\tproject")
        }
        let payload = lines.joined(separator: "\n") + "\n"
        do {
            try payload.write(to: out, atomically: true, encoding: .utf8)
            return map.count
        } catch {
            return 0
        }
    }

    static func extractSymbols(from text: String) -> [String] {
        // CamelCase or snake_case identifiers of reasonable length.
        let pattern = #"\b([A-Z][A-Za-z0-9]{3,}|[a-z]+(?:_[a-z0-9]+){1,}|[a-z]+[A-Z][A-Za-z0-9]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result: [String] = []
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  let swiftRange = Range(match.range(at: 1), in: text) else { return }
            let symbol = String(text[swiftRange])
            // Drop all-lowercase short noise and pure language keywords.
            let banned: Set<String> = [
                "func", "class", "struct", "enum", "return", "import", "public",
                "private", "static", "override", "guard", "throw", "async", "await",
                "true", "false", "null", "undefined", "const", "let", "var",
            ]
            if banned.contains(symbol.lowercased()) { return }
            result.append(symbol)
        }
        return result
    }

    private static func compact(_ value: String) -> String {
        value.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func gitBranches(in root: URL) -> [String]? {
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["branch", "--format=%(refname:short)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
