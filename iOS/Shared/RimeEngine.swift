import Foundation

struct RimeCandidate: Equatable, Sendable {
    let text: String
    let comment: String?
    /// Optional engine weight/source metadata used by a candidate ranker.
    /// Older bridge builds may omit both values and remain fully compatible.
    let rawWeight: Double?
    let source: String?

    init(text: String, comment: String?, rawWeight: Double? = nil, source: String? = nil) {
        self.text = text
        self.comment = comment
        self.rawWeight = rawWeight
        self.source = source
    }
}

struct RimeSnapshot: Equatable, Sendable {
    var preedit: String
    var candidates: [RimeCandidate]
    var highlightedIndex: Int
    /// Zero-based index of the candidate page being shown.
    var pageNumber: Int
    var isLastPage: Bool

    static let empty = RimeSnapshot(
        preedit: "",
        candidates: [],
        highlightedIndex: 0,
        pageNumber: 0,
        isLastPage: true
    )

    var isComposing: Bool { !preedit.isEmpty }
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

    /// Offers any printable ASCII character to the engine. Letters extend the
    /// composition; punctuation reaches the schema's punctuator. The outcome
    /// says whether the engine took the key, so the caller can type it instead.
    @discardableResult
    func process(character: Character) -> RimeKeyOutcome
    @discardableResult
    func backspace() -> RimeKeyOutcome
    @discardableResult
    func turnPage(forward: Bool) -> RimeKeyOutcome
    @discardableResult
    func selectCandidate(at index: Int) -> RimeKeyOutcome
    /// Absolute index into `allCandidates()`, for the expanded panel.
    @discardableResult
    func selectAbsoluteCandidate(at index: Int) -> RimeKeyOutcome
    /// Full candidate list for the current composition (across pages).
    func allCandidates() -> [RimeCandidate]
    func commitBestCandidate() -> String?
    func reset()
}

enum RimeEngineError: LocalizedError {
    case resourcesMissing
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .resourcesMissing:
            return MobileL10n.t(.rimeDictionaryMissing)
        case .appGroupUnavailable:
            return MobileL10n.t(.rimeContainerUnavailable)
        }
    }
}

/// Production wrapper around librime. The Objective-C++ bridge owns the native
/// session while this type keeps UIKit independent from the C API.
final class LibrimeEngine: RimeEngine {
    // X11 keysyms, which is what librime's process_key expects.
    private static let backspaceKeyCode = 0xff08
    private static let pageUpKeyCode = 0xff55
    private static let pageDownKeyCode = 0xff56

    private let bridge: VVRimeBridge

    init(
        sharedDataDirectory: URL,
        userDataDirectory: URL,
        stagingDirectory: URL?,
        performMaintenance: Bool,
        fullCheck: Bool
    ) throws {
        // Files created inside inherit the directory's protection class. What
        // librime learns is a record of what the user typed, so it should not
        // be readable from a powered-off device. Complete protection is too
        // strong: the LevelDB stays open across lock events and would start
        // failing its reads.
        try FileManager.default.createDirectory(
            at: userDataDirectory,
            withIntermediateDirectories: true,
            attributes: [
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
        bridge = try VVRimeBridge(
            sharedDataDirectory: sharedDataDirectory.path,
            userDataDirectory: userDataDirectory.path,
            stagingDirectory: stagingDirectory?.path,
            schemaID: RimeEngineFactory.selectedSchema.rawValue,
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
                comment: $0["comment"].flatMap { $0.isEmpty ? nil : $0 },
                rawWeight: $0["weight"].flatMap(Double.init),
                source: $0["source"].flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        let rawIndex = (value["highlightedIndex"] as? NSNumber)?.intValue ?? 0
        let highlightedIndex = candidates.indices.contains(rawIndex) ? rawIndex : 0
        return RimeSnapshot(
            preedit: preedit,
            candidates: candidates,
            highlightedIndex: highlightedIndex,
            pageNumber: (value["pageNumber"] as? NSNumber)?.intValue ?? 0,
            isLastPage: (value["isLastPage"] as? NSNumber)?.boolValue ?? true
        )
    }

    @discardableResult
    func process(character: Character) -> RimeKeyOutcome {
        guard character.isASCII,
              let scalar = character.unicodeScalars.first,
              (0x20...0x7e).contains(scalar.value) else {
            return .ignored(snapshot)
        }
        return outcome(from: bridge.processKeyCode(Int(scalar.value)))
    }

    @discardableResult
    func backspace() -> RimeKeyOutcome {
        outcome(from: bridge.processKeyCode(Self.backspaceKeyCode))
    }

    @discardableResult
    func turnPage(forward: Bool) -> RimeKeyOutcome {
        outcome(from: bridge.processKeyCode(
            forward ? Self.pageDownKeyCode : Self.pageUpKeyCode
        ))
    }

    @discardableResult
    func selectCandidate(at index: Int) -> RimeKeyOutcome {
        outcome(from: bridge.selectCandidate(at: index))
    }

    @discardableResult
    func selectAbsoluteCandidate(at index: Int) -> RimeKeyOutcome {
        outcome(from: bridge.selectAbsoluteCandidate(at: index))
    }

    func allCandidates() -> [RimeCandidate] {
        let raw = bridge.allCandidates() as? [[String: String]] ?? []
        let parsed = raw.compactMap { row -> RimeCandidate? in
            let text = row["text"] ?? ""
            guard !text.isEmpty else { return nil }
            return RimeCandidate(
                text: text,
                comment: row["comment"].flatMap { $0.isEmpty ? nil : $0 }
            )
        }
        if !parsed.isEmpty { return parsed }
        return collectCandidatesByPaging()
    }

    /// Walks every menu page when the absolute iterator is unavailable. Restores
    /// the page the user was on so expanding the sheet does not jump the bar.
    private func collectCandidatesByPaging() -> [RimeCandidate] {
        let startPage = snapshot.pageNumber
        while snapshot.pageNumber > 0 {
            _ = turnPage(forward: false)
        }
        var collected: [RimeCandidate] = []
        var guardCount = 0
        while guardCount < 40 {
            collected.append(contentsOf: snapshot.candidates)
            guardCount += 1
            if snapshot.isLastPage { break }
            _ = turnPage(forward: true)
        }
        while snapshot.pageNumber < startPage {
            _ = turnPage(forward: true)
        }
        return collected
    }

    func commitBestCandidate() -> String? {
        let current = snapshot
        if current.candidates.indices.contains(current.highlightedIndex) {
            return selectCandidate(at: current.highlightedIndex).commit
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
    private static let schemaDefaultsKey = "rime.schema"

    static var selectedSchema: RimeSchema {
        get {
            guard let raw = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: schemaDefaultsKey),
                  let schema = RimeSchema(rawValue: raw) else { return .simplifiedPinyin }
            return schema
        }
        set { UserDefaults(suiteName: appGroupIdentifier)?.set(newValue.rawValue, forKey: schemaDefaultsKey) }
    }

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

    /// Which of the three storage arrangements the keyboard ended up on. The
    /// keyboard behaves visibly differently on each, so a bug report is not
    /// actionable without knowing which one produced it.
    enum KeyboardEngineTier: String, Sendable {
        /// The schema the containing app deployed, read from the App Group.
        case sharedContainer
        /// librime deployed into the extension's own sandbox because the App
        /// Group was unreachable. Full dictionary, but learning is not shared.
        case localSandbox
        /// The ten-word fallback lexicon.
        case prototype
    }

    static func makeForKeyboard() -> KeyboardEngine {
        let started = Date()
        do {
            let deployment = try containerDirectory(named: deploymentFolder)
            let engine = try make(
                userDataDirectory: try containerDirectory(named: keyboardFolder),
                stagingDirectory: deployment.appendingPathComponent("build", isDirectory: true),
                performMaintenance: false
            )
            log(tier: .sharedContainer, since: started, reason: nil)
            return KeyboardEngine(engine: engine, degradedReason: nil)
        } catch let sharedContainerError {
            // Personal Team provisioning can display the App Group capability
            // in Xcode while omitting the entitlement from the installed
            // extension. The schemas are still bundled in RimeData, so deploy
            // them into the keyboard's own sandbox instead of falling all the
            // way back to the tiny prototype lexicon.
            do {
                let localRoot = try keyboardLocalRimeDirectory()
                let engine = try make(
                    userDataDirectory: localRoot.appendingPathComponent(keyboardFolder, isDirectory: true),
                    stagingDirectory: localRoot.appendingPathComponent("build", isDirectory: true),
                    performMaintenance: true
                )
                log(
                    tier: .localSandbox,
                    since: started,
                    reason: sharedContainerError.localizedDescription
                )
                return KeyboardEngine(engine: engine, degradedReason: nil)
            } catch {
                let reason = "\(sharedContainerError.localizedDescription) / \(error.localizedDescription)"
                log(tier: .prototype, since: started, reason: reason)
                return KeyboardEngine(
                    engine: PrototypeRimeEngine(),
                    degradedReason: reason
                )
            }
        }
    }

    private static func log(tier: KeyboardEngineTier, since: Date, reason: String?) {
        var fields = [
            "tier": tier.rawValue,
            "schema": selectedSchema.rawValue,
            "ms": String(Int(Date().timeIntervalSince(since) * 1000)),
        ]
        // The reason a tier was skipped is the whole diagnosis, and it is the
        // one thing the on-screen badge is too small to carry.
        if let reason { fields["reason"] = reason }
        MobileLog.emit(
            .rime,
            "keyboard.engine",
            level: tier == .sharedContainer ? .info : .error,
            fields
        )
    }

    private static func keyboardLocalRimeDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw RimeEngineError.appGroupUnavailable
        }
        let directory = applicationSupport.appendingPathComponent("Rime", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return directory
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

    /// Deletes everything librime has learned from the user while leaving the
    /// compiled schema in place, so clearing does not force a redeploy.
    ///
    /// Only safe to call from the containing app: the keyboard may hold the
    /// LevelDB open, and it reopens its own directory the next time it starts.
    static func clearLearningData() {
        let manager = FileManager.default
        if let keyboard = try? containerDirectory(named: keyboardFolder) {
            try? manager.removeItem(at: keyboard)
        }
        guard let deployment = try? containerDirectory(named: deploymentFolder),
              let contents = try? manager.contentsOfDirectory(
                at: deployment,
                includingPropertiesForKeys: nil
              ) else { return }
        for url in contents where url.lastPathComponent.contains(".userdb") {
            try? manager.removeItem(at: url)
        }
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
            highlightedIndex: 0,
            pageNumber: 0,
            isLastPage: true
        )
    }

    @discardableResult
    func process(character: Character) -> RimeKeyOutcome {
        guard character.isASCII, character.isLetter || character == "'" else {
            return .ignored(snapshot)
        }
        composition.append(Character(character.lowercased()))
        return RimeKeyOutcome(commit: nil, handled: true, snapshot: snapshot)
    }

    @discardableResult
    func backspace() -> RimeKeyOutcome {
        guard !composition.isEmpty else { return .ignored(snapshot) }
        composition.removeLast()
        return RimeKeyOutcome(commit: nil, handled: true, snapshot: snapshot)
    }

    /// The fallback lexicon never produces more than one page.
    @discardableResult
    func turnPage(forward: Bool) -> RimeKeyOutcome {
        .ignored(snapshot)
    }

    func selectCandidate(at index: Int) -> RimeKeyOutcome {
        let current = snapshot
        guard current.candidates.indices.contains(index) else {
            return .ignored(current)
        }
        let text = current.candidates[index].text
        reset()
        return RimeKeyOutcome(commit: text, handled: true, snapshot: snapshot)
    }

    func selectAbsoluteCandidate(at index: Int) -> RimeKeyOutcome {
        selectCandidate(at: index)
    }

    func allCandidates() -> [RimeCandidate] {
        snapshot.candidates
    }

    func commitBestCandidate() -> String? {
        selectCandidate(at: snapshot.highlightedIndex).commit
    }

    func reset() {
        composition = ""
    }
}
