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

/// What one key did to the composition.
struct RimeKeyOutcome: Equatable, Sendable {
    /// Text the engine committed because of this key. The engine has already
    /// dropped it from the composition, so the host has to insert it now.
    var commit: String?
    /// False when the engine did not consume the key and the host should.
    var handled: Bool
    var snapshot: RimeSnapshot

    static func ignored(_ snapshot: RimeSnapshot) -> RimeKeyOutcome {
        RimeKeyOutcome(commit: nil, handled: false, snapshot: snapshot)
    }
}

protocol RimeEngine: AnyObject {
    var snapshot: RimeSnapshot { get }

    @discardableResult
    func process(letter: Character) -> RimeKeyOutcome
    @discardableResult
    func backspace() -> RimeKeyOutcome
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
    private static let backspaceKeyCode = 0xff08

    private let bridge: VVRimeBridge

    init(
        sharedDataDirectory: URL,
        userDataDirectory: URL,
        stagingDirectory: URL?,
        performMaintenance: Bool,
        fullCheck: Bool
    ) throws {
        try FileManager.default.createDirectory(
            at: userDataDirectory,
            withIntermediateDirectories: true
        )
        bridge = try VVRimeBridge(
            sharedDataDirectory: sharedDataDirectory.path,
            userDataDirectory: userDataDirectory.path,
            stagingDirectory: stagingDirectory?.path,
            performMaintenance: performMaintenance,
            fullCheck: fullCheck
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
    func process(letter: Character) -> RimeKeyOutcome {
        guard letter.isASCII, letter.isLetter || letter == "'",
              let scalar = String(letter.lowercased()).unicodeScalars.first else {
            return .ignored(snapshot)
        }
        return outcome(from: bridge.processKeyCode(Int(scalar.value)))
    }

    @discardableResult
    func backspace() -> RimeKeyOutcome {
        outcome(from: bridge.processKeyCode(Self.backspaceKeyCode))
    }

    func selectCandidate(at index: Int) -> String? {
        bridge.selectCandidate(at: index)
    }

    func commitBestCandidate() -> String? {
        let current = snapshot
        if current.candidates.indices.contains(current.highlightedIndex) {
            return selectCandidate(at: current.highlightedIndex)
        }
        return bridge.commitComposition()
    }

    func reset() {
        bridge.clearComposition()
    }

    private func outcome(from result: VVRimeKeyResult) -> RimeKeyOutcome {
        RimeKeyOutcome(commit: result.commit, handled: result.handled, snapshot: snapshot)
    }
}

enum RimeEngineFactory {
    static let appGroupIdentifier = "group.app.vibevoice.oss.shared"

    /// The containing app deploys here, so this directory holds the compiled
    /// schema both processes read.
    private static let deploymentFolder = "Deploy"
    /// The keyboard learns into its own database. librime keeps the user
    /// dictionary in a LevelDB, which permits a single writer, so pointing both
    /// processes at one directory makes whichever opens second fail and fall
    /// back to the prototype engine.
    private static let keyboardFolder = "KeyboardUser"

    struct KeyboardEngine {
        let engine: RimeEngine
        /// Set when librime could not start and the deterministic fallback is in
        /// use. Without surfacing it the keyboard silently appears to forget
        /// almost every word.
        let degradedReason: String?
    }

    static func makeForKeyboard() -> KeyboardEngine {
        do {
            let deployment = try containerDirectory(named: deploymentFolder)
            let engine = try make(
                userDataDirectory: try containerDirectory(named: keyboardFolder),
                stagingDirectory: deployment.appendingPathComponent("build", isDirectory: true),
                performMaintenance: false
            )
            return KeyboardEngine(engine: engine, degradedReason: nil)
        } catch {
            return KeyboardEngine(
                engine: PrototypeRimeEngine(),
                degradedReason: error.localizedDescription
            )
        }
    }

    /// - Parameter fullCheck: re-verifies every dictionary. Only worth the cost
    ///   when the user explicitly asks to repair the deployment; a normal launch
    ///   lets librime deploy just what changed.
    static func prepareForMainApp(fullCheck: Bool) throws -> RimeEngine {
        try make(
            userDataDirectory: try containerDirectory(named: deploymentFolder),
            performMaintenance: true,
            fullCheck: fullCheck
        )
    }

    static func make(
        bundle: Bundle = .main,
        userDataDirectory: URL,
        stagingDirectory: URL? = nil,
        performMaintenance: Bool,
        fullCheck: Bool = false
    ) throws -> LibrimeEngine {
        guard let sharedDataDirectory = rimeDataDirectory(in: bundle) else {
            throw RimeEngineError.resourcesMissing
        }
        return try LibrimeEngine(
            sharedDataDirectory: sharedDataDirectory,
            userDataDirectory: userDataDirectory,
            stagingDirectory: stagingDirectory,
            performMaintenance: performMaintenance,
            fullCheck: fullCheck
        )
    }

    /// Everything librime writes lives under this directory, so it is also what
    /// a "clear learning data" action removes.
    static func containerDirectory(named name: String) throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw RimeEngineError.appGroupUnavailable
        }
        return container
            .appendingPathComponent("Rime", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    static var keyboardLearningDirectory: URL? {
        try? containerDirectory(named: keyboardFolder)
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
    func process(letter: Character) -> RimeKeyOutcome {
        guard letter.isASCII, letter.isLetter || letter == "'" else {
            return .ignored(snapshot)
        }
        composition.append(Character(letter.lowercased()))
        return RimeKeyOutcome(commit: nil, handled: true, snapshot: snapshot)
    }

    @discardableResult
    func backspace() -> RimeKeyOutcome {
        guard !composition.isEmpty else { return .ignored(snapshot) }
        composition.removeLast()
        return RimeKeyOutcome(commit: nil, handled: true, snapshot: snapshot)
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
