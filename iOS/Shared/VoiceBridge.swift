import Foundation

enum VoiceBridgeStatus: String, Codable, Sendable {
    case idle
    case requested
    case recording
    case processing
    case ready
    case consumed
    case failed

    /// The raw values are persistence keys shared across two processes, so they
    /// stay as stable identifiers and the wording lives here instead.
    var displayName: String {
        switch self {
        case .idle: MobileL10n.t(.bridgeStatusIdle)
        case .requested: MobileL10n.t(.bridgeStatusRequested)
        case .recording: MobileL10n.t(.bridgeStatusRecording)
        case .processing: MobileL10n.t(.bridgeStatusProcessing)
        case .ready: MobileL10n.t(.bridgeStatusReady)
        case .consumed: MobileL10n.t(.bridgeStatusConsumed)
        case .failed: MobileL10n.t(.bridgeStatusFailed)
        }
    }
}

struct VoiceBridgeState: Codable, Equatable, Sendable {
    /// A transcript older than this is never inserted on its own. Speech that the
    /// user has forgotten about must not surface in whatever they type next.
    static let readyLifetime: TimeInterval = 300

    var requestID: UUID
    var status: VoiceBridgeStatus
    var mode: VoiceOutputMode
    /// The text field that asked for dictation, so the result can be delivered
    /// back to that field only. `nil` when no field is waiting for a result.
    var targetDocumentID: UUID?
    var text: String
    var message: String
    var updatedAt: Date

    static var idle: VoiceBridgeState {
        VoiceBridgeState(
            requestID: UUID(),
            status: .idle,
            mode: .polished,
            targetDocumentID: nil,
            text: "",
            message: "",
            updatedAt: Date()
        )
    }

    /// A transcript is available and recent enough to be worth inserting.
    func hasFreshResult(now: Date = Date()) -> Bool {
        status == .ready
            && !text.isEmpty
            && now.timeIntervalSince(updatedAt) <= Self.readyLifetime
    }

    /// `documentID` is the field that requested this dictation.
    func targets(documentID: UUID?) -> Bool {
        guard let targetDocumentID, let documentID else { return false }
        return targetDocumentID == documentID
    }

    /// What the keyboard should do with this state for the field it is
    /// currently attached to. It lives here rather than in the view controller
    /// so the rule deciding where transcribed speech ends up can be tested
    /// without a host application.
    func delivery(
        toDocument documentID: UUID?,
        alreadyInserted: UUID?,
        now: Date = Date()
    ) -> VoiceBridgeDelivery {
        guard hasFreshResult(now: now), requestID != alreadyInserted else { return .nothing }
        return targets(documentID: documentID) ? .insert(self) : .awaitExplicitInsert(self)
    }
}

enum VoiceBridgeDelivery: Equatable, Sendable {
    /// This field asked for the dictation, so insert it.
    case insert(VoiceBridgeState)
    /// A result exists but belongs to another field. Inserting it here would
    /// put speech somewhere the user never asked for it, so wait for a tap.
    case awaitExplicitInsert(VoiceBridgeState)
    case nothing
}

/// Cross-process handoff between the keyboard extension and the containing app.
///
/// The state lives in a coordinated file in the App Group container rather than
/// in shared `UserDefaults`. `cfprefsd` caches preference reads per process, so
/// the extension can keep seeing a stale value after the app writes, and the
/// read-modify-write updates both sides perform would silently lose each other.
/// `NSFileCoordinator` gives a consistent view and serialises mutations.
final class VoiceBridgeStore {
    static let appGroupID = "group.app.vibevoice.oss.shared"

    /// Builds before 0.7.0 kept the transcript here and never cleared it.
    private static let legacyDefaultsKey = "voiceBridge.state.v1"
    private static let fileName = "voice-bridge.v2.json"

    private let fileURL: URL
    private let usesFileCoordinator: Bool
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let sharedContainerAvailable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) != nil
        // Free Personal Team profiles may omit App Group entitlements. In that
        // case NSFileCoordinator can trigger filecoordinationd/XPC failures in
        // a keyboard extension, so use its private container without trying to
        // coordinate a file that cannot be shared anyway.
        usesFileCoordinator = directory != nil || sharedContainerAvailable
        let base = directory ?? Self.defaultDirectory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(Self.fileName, isDirectory: false)
        Self.purgeLegacyPlaintextState()

        // Losing the shared container is the failure that looks like nothing:
        // both processes keep working, each against its own copy of the state,
        // and dictation simply never arrives. Say so once, at the only moment
        // the answer is known.
        guard directory == nil else { return }
        MobileLog.emit(
            .bridge,
            "store.opened",
            level: sharedContainerAvailable ? .info : .error,
            [
                "appGroup": String(sharedContainerAvailable),
                "coordinated": String(usesFileCoordinator),
                "detail": sharedContainerAvailable
                    ? "shared container"
                    : "app group entitlement missing; this process is isolated",
            ]
        )
    }

    func load() -> VoiceBridgeState {
        guard usesFileCoordinator else { return decodeState(at: fileURL) ?? .idle }
        var state = VoiceBridgeState.idle
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { url in
            state = decodeState(at: url) ?? state
        }
        return state
    }

    @discardableResult
    func request(mode: VoiceOutputMode, documentID: UUID?) -> VoiceBridgeState {
        mutate { state in
            state.requestID = UUID()
            state.status = .requested
            state.mode = mode
            state.targetDocumentID = documentID
            state.text = ""
            state.message = MobileL10n.t(.bridgeOpenAppToRecord)
        }
    }

    @discardableResult
    func publish(
        status: VoiceBridgeStatus,
        text: String = "",
        message: String = ""
    ) -> VoiceBridgeState {
        mutate { state in
            state.status = status
            state.text = text
            state.message = message
        }
    }

    @discardableResult
    func setMode(_ mode: VoiceOutputMode) -> VoiceBridgeState {
        mutate { $0.mode = mode }
    }

    /// Drops the transcript along with the status. A result that has been
    /// inserted must not stay readable in the shared container afterwards.
    @discardableResult
    func markConsumed(requestID: UUID) -> VoiceBridgeState {
        mutate { state in
            guard state.requestID == requestID else { return }
            state.status = .consumed
            state.text = ""
            state.targetDocumentID = nil
        }
    }

    /// Turns a recording or transcription that the system killed into an
    /// actionable failure instead of a phase the UI can never leave.
    @discardableResult
    func recoverInterruptedWork() -> Bool {
        let before = load()
        guard before.status == .recording || before.status == .processing else {
            return false
        }
        mutate { state in
            guard state.status == .recording || state.status == .processing else { return }
            state.status = .failed
            state.text = ""
            state.message = MobileL10n.t(.bridgeInterrupted)
        }
        let after = load()
        return after.status == .failed && after.requestID == before.requestID
    }

    @discardableResult
    func reset() -> VoiceBridgeState {
        mutate { $0 = .idle }
    }

    // MARK: - Coordinated storage

    @discardableResult
    private func mutate(_ transform: (inout VoiceBridgeState) -> Void) -> VoiceBridgeState {
        guard usesFileCoordinator else {
            var state = decodeState(at: fileURL) ?? .idle
            let original = state
            transform(&state)
            guard state != original else { return state }
            state.updatedAt = Date()
            writeState(state, to: fileURL)
            log(original, state)
            return state
        }
        var result = VoiceBridgeState.idle
        var changed = false
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL,
            options: .forMerging,
            error: &coordinationError
        ) { url in
            var state = decodeState(at: url) ?? .idle
            let original = state
            transform(&state)
            guard state != original else {
                result = state
                return
            }
            state.updatedAt = Date()
            writeState(state, to: url)
            log(original, state)
            result = state
            changed = true
        }
        // A coordination failure means this write never reached the file the
        // other process reads, which is indistinguishable from "nothing
        // happened" unless it is reported.
        if let coordinationError {
            MobileLog.error(.bridge, "write.uncoordinated", [
                "error": coordinationError.domain + "/\(coordinationError.code)",
            ])
        }
        if changed {
            VoiceBridgeSignal.postChange()
        }
        return result
    }

    /// Records a state transition. The transcript itself never enters the log;
    /// its fingerprint is enough to match what the app produced against what
    /// the keyboard inserted.
    private func log(_ before: VoiceBridgeState, _ after: VoiceBridgeState) {
        MobileLog.info(.bridge, "state.changed", [
            "from": before.status.rawValue,
            "to": after.status.rawValue,
            "mode": after.mode.rawValue,
            "request": after.requestID.uuidString.prefix(8).lowercased(),
            "target": after.targetDocumentID?.uuidString.prefix(8).lowercased() ?? "none",
            "text": MobileLog.fingerprint(after.text),
        ])
    }

    private func decodeState(at url: URL) -> VoiceBridgeState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(VoiceBridgeState.self, from: data)
    }

    private func writeState(_ state: VoiceBridgeState, to url: URL) {
        guard let data = try? encoder.encode(state) else { return }
        // The payload is transcribed speech. Keep it unreadable while the device
        // is locked; neither the app nor a keyboard extension runs locked.
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func defaultDirectory() -> URL {
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        )
        return (container ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("VoiceBridge", isDirectory: true)
    }

    /// Deletes the plaintext transcript that older builds left in App Group
    /// `UserDefaults`, where it outlived the insertion that consumed it.
    private static func purgeLegacyPlaintextState() {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil,
              let defaults = UserDefaults(suiteName: appGroupID),
              defaults.object(forKey: legacyDefaultsKey) != nil else { return }
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
