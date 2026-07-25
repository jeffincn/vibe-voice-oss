import Foundation

struct RimeCandidate: Equatable, Sendable {
    let text: String
    let comment: String?
}

struct RimeSnapshot: Equatable, Sendable {
    var preedit: String
    var candidates: [RimeCandidate]
    var highlightedIndex: Int

    static let empty = RimeSnapshot(preedit: "", candidates: [], highlightedIndex: 0)
}

protocol RimeEngine: AnyObject {
    var snapshot: RimeSnapshot { get }

    @discardableResult
    func process(letter: Character) -> RimeSnapshot
    @discardableResult
    func backspace() -> RimeSnapshot
    func selectCandidate(at index: Int) -> String?
    func commitBestCandidate() -> String?
    func reset()
}

enum RimeEngineError: LocalizedError {
    case resourcesMissing
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return "应用内缺少 Rime 拼音词库。"
        case .appGroupUnavailable:
            return "无法访问键盘共享容器。"
        }
    }
}

/// Production wrapper around librime. The Objective-C++ bridge owns the native
/// session while this type keeps UIKit independent from the C API.
final class LibrimeEngine: RimeEngine {
    private let bridge: VVRimeBridge
    private var lastCommit: String?

    init(
        sharedDataDirectory: URL,
        userDataDirectory: URL,
        performMaintenance: Bool
    ) throws {
        try FileManager.default.createDirectory(
            at: userDataDirectory,
            withIntermediateDirectories: true
        )
        bridge = try VVRimeBridge(
            sharedDataDirectory: sharedDataDirectory.path,
            userDataDirectory: userDataDirectory.path,
            performMaintenance: performMaintenance
        )
    }

    var snapshot: RimeSnapshot {
        let value = bridge.snapshot()
        let preedit = value["preedit"] as? String ?? ""
        let rawCandidates = value["candidates"] as? [[String: String]] ?? []
        let candidates = rawCandidates.map {
            RimeCandidate(
                text: $0["text"] ?? "",
                comment: $0["comment"].flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        let rawIndex = (value["highlightedIndex"] as? NSNumber)?.intValue ?? 0
        let highlightedIndex = candidates.indices.contains(rawIndex) ? rawIndex : 0
        return RimeSnapshot(
            preedit: preedit,
            candidates: candidates,
            highlightedIndex: highlightedIndex
        )
    }

    @discardableResult
    func process(letter: Character) -> RimeSnapshot {
        guard letter.isASCII, letter.isLetter || letter == "'",
              let scalar = String(letter.lowercased()).unicodeScalars.first else {
            return snapshot
        }
        lastCommit = bridge.processKeyCode(Int(scalar.value))
        return snapshot
    }

    @discardableResult
    func backspace() -> RimeSnapshot {
        lastCommit = bridge.processKeyCode(0xff08)
        return snapshot
    }

    func selectCandidate(at index: Int) -> String? {
        bridge.selectCandidate(at: index)
    }

    func commitBestCandidate() -> String? {
        if let lastCommit {
            self.lastCommit = nil
            return lastCommit
        }
        let current = snapshot
        if current.candidates.indices.contains(current.highlightedIndex) {
            return selectCandidate(at: current.highlightedIndex)
        }
        return bridge.commitComposition()
    }

    func reset() {
        lastCommit = nil
        bridge.clearComposition()
    }
}

enum RimeEngineFactory {
    static let appGroupIdentifier = "group.app.vibevoice.oss.shared"

    static func makeForKeyboard() -> RimeEngine {
        do {
            return try make(performMaintenance: false)
        } catch {
            return PrototypeRimeEngine()
        }
    }

    static func prepareForMainApp() throws -> RimeEngine {
        try make(performMaintenance: true)
    }

    static func make(
        bundle: Bundle = .main,
        userDataDirectory: URL? = nil,
        performMaintenance: Bool
    ) throws -> LibrimeEngine {
        guard let sharedDataDirectory = rimeDataDirectory(in: bundle) else {
            throw RimeEngineError.resourcesMissing
        }
        let resolvedUserDirectory: URL
        if let userDataDirectory {
            resolvedUserDirectory = userDataDirectory
        } else {
            guard let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            ) else {
                throw RimeEngineError.appGroupUnavailable
            }
            resolvedUserDirectory = container
                .appendingPathComponent("Rime", isDirectory: true)
                .appendingPathComponent("User", isDirectory: true)
        }
        return try LibrimeEngine(
            sharedDataDirectory: sharedDataDirectory,
            userDataDirectory: resolvedUserDirectory,
            performMaintenance: performMaintenance
        )
    }

    private static func rimeDataDirectory(in bundle: Bundle) -> URL? {
        if let folder = bundle.url(forResource: "RimeData", withExtension: nil) {
            return folder
        }
        guard let resources = bundle.resourceURL,
              FileManager.default.fileExists(
                atPath: resources.appendingPathComponent("vibe_pinyin.schema.yaml").path
              ) else {
            return nil
        }
        return resources
    }
}

/// Deterministic emergency fallback. It preserves basic Chinese input if Rime
/// deployment has not yet completed, while the main app explains how to repair it.
final class PrototypeRimeEngine: RimeEngine {
    private static let lexicon: [String: [String]] = [
        "ni": ["你", "呢", "尼", "泥", "拟"],
        "hao": ["好", "号", "浩", "豪", "毫"],
        "nihao": ["你好", "拟好"],
        "wo": ["我", "握", "窝", "卧"],
        "shi": ["是", "时", "事", "市", "十"],
        "zhong": ["中", "种", "重", "众"],
        "guo": ["国", "过", "果", "锅"],
        "zhongguo": ["中国"],
        "shuru": ["输入"],
        "shurufa": ["输入法"],
    ]

    private var composition = ""

    var snapshot: RimeSnapshot {
        guard !composition.isEmpty else { return .empty }
        let words = Self.lexicon[composition] ?? [composition]
        return RimeSnapshot(
            preedit: composition,
            candidates: words.map { RimeCandidate(text: $0, comment: nil) },
            highlightedIndex: 0
        )
    }

    @discardableResult
    func process(letter: Character) -> RimeSnapshot {
        guard letter.isASCII, letter.isLetter || letter == "'" else { return snapshot }
        composition.append(Character(letter.lowercased()))
        return snapshot
    }

    @discardableResult
    func backspace() -> RimeSnapshot {
        if !composition.isEmpty {
            composition.removeLast()
        }
        return snapshot
    }

    func selectCandidate(at index: Int) -> String? {
        let current = snapshot
        guard current.candidates.indices.contains(index) else { return nil }
        let text = current.candidates[index].text
        reset()
        return text
    }

    func commitBestCandidate() -> String? {
        selectCandidate(at: snapshot.highlightedIndex)
    }

    func reset() {
        composition = ""
    }
}
