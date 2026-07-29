import CryptoKit
import Foundation
import os

/// The part of the product an event came from. The raw value is the os_log
/// category, so it is also what `--predicate 'category == "bridge"'` matches.
enum DiagnosticArea: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case host
    case bridge
    case rime
    case insertion
    case voice
    case model
}

enum DiagnosticLevel: String, Codable, Sendable {
    case debug
    case info
    case error
}

/// Which process wrote an event. The keyboard and the app are separate
/// processes with separate log files, so the merged view has to say which side
/// of the bridge it is looking at.
enum DiagnosticProcess: String, Codable, Sendable {
    case app
    case keyboard

    static let current: DiagnosticProcess = {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".keyboard") ? .keyboard : .app
    }()
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
    var timestamp: Date
    var process: DiagnosticProcess
    var area: DiagnosticArea
    var level: DiagnosticLevel
    var name: String
    /// The host application being typed into, as labelled by whoever is
    /// running the test. iOS tells a keyboard extension nothing about its host,
    /// so this is the only way an event can name the channel it came from.
    var channel: String?
    var fields: [String: String]

    /// One line of `key=value`, ordered so two events of the same kind can be
    /// diffed by eye in a terminal.
    var fieldSummary: String {
        fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: " ")
    }

    var line: String {
        let stamp = DiagnosticEvent.stampFormatter.string(from: timestamp)
        let label = channel.map { "[\($0)] " } ?? ""
        return "\(stamp) \(process.rawValue)/\(area.rawValue) \(label)\(name) \(fieldSummary)"
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}

/// Diagnostics for the iOS targets.
///
/// Every event goes to two places, because neither one alone can debug a
/// keyboard extension in a real app:
///
/// - `os_log`, which is live but only readable while a Mac is attached, and
///   which the system may drop under pressure.
/// - A per-process JSON Lines file in the App Group container, which survives
///   the extension being killed and can be pulled off the device afterwards
///   with `devicectl device copy from --domain-type appGroupDataContainer`.
///
/// The durable file is written with `completeUntilFirstUserAuthentication`
/// rather than the `completeFileProtection` the voice bridge uses. Complete
/// protection makes a file unreadable to the device's file-transfer service,
/// which would defeat the entire point of writing it. That is only acceptable
/// because of the rule below.
///
/// **No event may carry what the user typed, said, or transcribed.** Text is
/// admitted only through `fingerprint(_:)`, which keeps a length and a
/// truncated digest — enough to prove "the same string arrived" without
/// storing the string.
enum MobileLog {
    static let subsystem = "app.vibevoice.oss"

    private static let loggers: [DiagnosticArea: Logger] = Dictionary(
        uniqueKeysWithValues: DiagnosticArea.allCases.map {
            ($0, Logger(subsystem: subsystem, category: $0.rawValue))
        }
    )

    // MARK: - Emitting

    static func debug(_ area: DiagnosticArea, _ name: String, _ fields: [String: String] = [:]) {
        emit(area, name, level: .debug, fields)
    }

    static func info(_ area: DiagnosticArea, _ name: String, _ fields: [String: String] = [:]) {
        emit(area, name, level: .info, fields)
    }

    static func error(_ area: DiagnosticArea, _ name: String, _ fields: [String: String] = [:]) {
        emit(area, name, level: .error, fields)
    }

    static func emit(
        _ area: DiagnosticArea,
        _ name: String,
        level: DiagnosticLevel,
        _ fields: [String: String] = [:]
    ) {
        // Debug events are the high-frequency ones — every keystroke, every
        // bridge poll. They stay off until someone turns them on for a session,
        // so ordinary use does not spend battery writing a log nobody reads.
        guard level != .debug || DiagnosticSettings.isVerbose else { return }

        let event = DiagnosticEvent(
            timestamp: Date(),
            process: .current,
            area: area,
            level: level,
            name: name,
            channel: DiagnosticSettings.channelLabel,
            fields: fields
        )

        // `.public` is safe here and necessary: os_log redacts dynamic strings
        // by default, and a log of `<private>` is worth nothing. The fields
        // reaching this point are already free of user content.
        let logger = loggers[area] ?? Logger(subsystem: subsystem, category: area.rawValue)
        let rendered = "\(event.process.rawValue) \(name) \(event.fieldSummary)"
        switch level {
        case .debug: logger.debug("\(rendered, privacy: .public)")
        case .info: logger.info("\(rendered, privacy: .public)")
        case .error: logger.error("\(rendered, privacy: .public)")
        }

        DiagnosticStore.shared.append(event)
    }

    // MARK: - Redaction

    /// The only sanctioned way for user text to influence a diagnostic.
    ///
    /// Returns something like `len=6 sha=1a2b3c4d`. Two identical strings
    /// produce the same digest, which is what makes it possible to prove that
    /// the text the keyboard inserted is the text that reached the document,
    /// without either side of that comparison being stored in the clear.
    static func fingerprint(_ text: String) -> String {
        guard !text.isEmpty else { return "len=0" }
        let digest = SHA256.hash(data: Data(text.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "len=\(text.count) sha=\(hex)"
    }
}

/// Session switches, in App Group `UserDefaults` so the containing app can turn
/// them on and the keyboard extension picks them up on its next read.
///
/// `UserDefaults` is the right store here even though the voice bridge had to
/// abandon it: these are read often and written rarely by exactly one process,
/// which is the case `cfprefsd`'s per-process caching handles correctly.
enum DiagnosticSettings {
    static let appGroupID = "group.app.vibevoice.oss.shared"
    private static let verboseKey = "diagnostics.verbose"
    private static let channelKey = "diagnostics.channelLabel"
    private static let verifyInsertionKey = "diagnostics.verifyInsertion"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// Admits `.debug` events. Off by default.
    static var isVerbose: Bool {
        get { defaults?.bool(forKey: verboseKey) ?? false }
        set { defaults?.set(newValue, forKey: verboseKey) }
    }

    /// Re-reads the document after every insertion to confirm the text landed.
    /// Costs an extra proxy round trip per keystroke, so it is opt-in, but it
    /// is the only thing that can tell a host that silently drops text from a
    /// keyboard that never sent any.
    static var verifiesInsertion: Bool {
        get { defaults?.bool(forKey: verifyInsertionKey) ?? false }
        set { defaults?.set(newValue, forKey: verifyInsertionKey) }
    }

    /// Names the app currently being typed into, e.g. `WeChat`. Set by hand in
    /// the app's Diagnostics screen before switching to the host under test.
    static var channelLabel: String? {
        get {
            let raw = defaults?.string(forKey: channelKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty ?? true) ? nil : raw
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                defaults?.set(trimmed, forKey: channelKey)
            } else {
                defaults?.removeObject(forKey: channelKey)
            }
        }
    }
}

/// Append-only event storage, one file per process.
///
/// The two processes never write the same file, which is deliberate: a shared
/// file would need `NSFileCoordinator` on every event, and coordinating from a
/// keyboard extension is exactly the operation that fails when the App Group
/// entitlement is missing — the case this log exists to diagnose.
final class DiagnosticStore: @unchecked Sendable {
    static let shared = DiagnosticStore()

    /// Roughly a long test session. The file is trimmed to half this when it is
    /// exceeded, so the cost is paid rarely rather than on every write.
    private static let maxBytes = 512 * 1024
    private static let directoryName = "Diagnostics"

    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let directory: URL?

    private init() {
        directory = Self.makeDirectory()
    }

    /// Test seam. The shared instance writes into a container that only exists
    /// on a device, and trimming and merging are the parts most worth checking.
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var fileURL: URL? { url(for: .current) }

    private func url(for process: DiagnosticProcess) -> URL? {
        directory?.appendingPathComponent("\(process.rawValue).jsonl", isDirectory: false)
    }

    func append(_ event: DiagnosticEvent) {
        guard let fileURL,
              var data = try? encoder.encode(event) else { return }
        data.append(0x0a)

        lock.lock()
        defer { lock.unlock() }

        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            manager.createFile(
                atPath: fileURL.path,
                contents: data,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            return
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        let end = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
        guard let end, end > UInt64(Self.maxBytes) else { return }
        trim(fileURL)
    }

    /// Every event both processes have written, oldest first.
    func allEvents() -> [DiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return [DiagnosticProcess.app, .keyboard]
            .compactMap { url(for: $0) }
            .flatMap(decodeEvents(at:))
            .sorted { $0.timestamp < $1.timestamp }
    }

    func recentEvents(limit: Int) -> [DiagnosticEvent] {
        Array(allEvents().suffix(limit))
    }

    /// A plain-text transcript suitable for a share sheet or a bug report.
    func export() -> String {
        allEvents().map(\.line).joined(separator: "\n")
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        for process in [DiagnosticProcess.app, .keyboard] {
            guard let url = url(for: process) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Where the log actually landed, so the Diagnostics screen can say whether
    /// it went to the shared container or to a private one the other process
    /// cannot see.
    var storageDescription: String {
        guard let directory else { return "unavailable" }
        return directory.path.contains("/Shared/AppGroup/") ? "app group" : "private container"
    }

    private func decodeEvents(at url: URL) -> [DiagnosticEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(DiagnosticEvent.self, from: Data($0.utf8)) }
    }

    /// Drops the oldest half. Cutting at a newline keeps the survivors parseable.
    private func trim(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let tail = data.suffix(Self.maxBytes / 2)
        guard let newline = tail.firstIndex(of: 0x0a) else { return }
        let aligned = tail[tail.index(after: newline)...]
        try? Data(aligned).write(to: url, options: [.atomic])
    }

    /// Picks the first container this process can actually write into.
    ///
    /// A keyboard extension without Full Access still resolves the App Group
    /// URL: the entitlement is present, and the sandbox refuses the write
    /// itself rather than the lookup. So asking for the container proves
    /// nothing, and a log that trusted the answer would discard every event in
    /// the one configuration it most needs to explain. The probe is a real
    /// write because `createDirectory` also succeeds on a directory that
    /// already exists and is read-only to us — which is exactly what the app
    /// leaves behind for the keyboard to find.
    private static func makeDirectory() -> URL? {
        let manager = FileManager.default
        let bases = [
            manager.containerURL(forSecurityApplicationGroupIdentifier: DiagnosticSettings.appGroupID),
            manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        ]
        for base in bases.compactMap({ $0 }) {
            let directory = base.appendingPathComponent(directoryName, isDirectory: true)
            do {
                try manager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
            } catch {
                continue
            }
            let probe = directory.appendingPathComponent(".writable", isDirectory: false)
            guard manager.createFile(atPath: probe.path, contents: Data()) else { continue }
            try? manager.removeItem(at: probe)
            return directory
        }
        return nil
    }
}
