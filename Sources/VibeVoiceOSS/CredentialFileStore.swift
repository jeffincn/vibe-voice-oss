import Foundation

/// Clear-text credential storage for builds that cannot use the Keychain.
///
/// Ad-hoc signatures change on every rebuild, so a Keychain ACL bound to the
/// designated requirement would prompt for the login password on every launch.
/// Those builds need somewhere else to keep API keys, and this is that place.
///
/// It is a hardening step over `UserDefaults`, not confidentiality:
///   - values stay out of the preferences plist, so `defaults read`, preference
///     syncing and plist-wide diagnostics no longer surface them
///   - the file is mode 0600 inside a mode 0700 directory
///   - the file is excluded from backups, so keys don't reach Time Machine
///
/// Anything running as the same user can still read it. A certificate-signed
/// build, which keeps keys in the Keychain, is the only properly protected setup.
final class CredentialFileStore: @unchecked Sendable {
    static let shared = CredentialFileStore(directory: defaultDirectory)

    private let directory: URL
    private let fileURL: URL
    private let lock = NSLock()

    init(directory: URL) {
        self.directory = directory
        fileURL = directory.appendingPathComponent("credentials.json", isDirectory: false)
    }

    func value(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let stored = load()[account]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !stored.isEmpty else {
            return nil
        }
        return stored
    }

    func set(_ value: String, for account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            remove(account)
            return
        }
        lock.lock()
        defer { lock.unlock() }
        var entries = load()
        guard entries[account] != trimmed else { return }
        entries[account] = trimmed
        persist(entries)
    }

    func remove(_ account: String) {
        lock.lock()
        defer { lock.unlock() }
        var entries = load()
        guard entries.removeValue(forKey: account) != nil else { return }
        persist(entries)
    }

    // MARK: - Storage

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func persist(_ entries: [String: String]) {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // `createDirectory` only applies attributes to directories it creates, and
        // this directory is shared with the usage database, so it may predate us.
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        guard !entries.isEmpty else {
            try? manager.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        guard (try? data.write(to: fileURL, options: [.atomic])) != nil else { return }
        // An atomic write swaps in a fresh inode, so the mode has to be re-applied.
        // The 0700 directory covers the brief window where the temporary file exists.
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        excludeFromBackup()
    }

    private func excludeFromBackup() {
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static var defaultDirectory: URL {
        guard KeychainStore.isRunningInTests else { return PersistenceDirectory.url }
        // Unit tests must never read or write the developer's real credentials.
        return FileManager.default.temporaryDirectory.appendingPathComponent(
            "VibeVoiceOSSTests-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
    }
}
