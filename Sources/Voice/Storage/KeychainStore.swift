import Foundation
import Security

/// Stores API keys in the macOS Keychain when the app has a stable code-signing
/// identity, falling back to a restricted local file otherwise.
///
/// Keychain item ACLs are bound to the app's designated requirement. With a
/// persistent certificate (Apple Development / local self-signed, see
/// scripts/build-app.sh) the requirement survives rebuilds, so reads never
/// trigger the login-password dialog. Ad-hoc signatures change on every build
/// and would prompt each time, so those builds fall back to
/// ``CredentialFileStore``.
enum KeychainStore {
    static let service = "app.vibevoice.oss.macos"
    /// Preference domain used by the pre-open-source local build.
    static let legacyPreferenceDomain = "local.vibe.voice-input"
    /// Previous OSS bundle preference / keychain service before the full rename.
    static let previousServices = ["app.vibevoice.macos"]
    static let previousPreferenceDomains = ["app.vibevoice.macos"]

    enum Account: String {
        case asrAPIKey = "asr.apiKey"
        case llmAPIKey = "llm.apiKey"
    }

    /// True when secrets should live in the Keychain: the running binary carries a
    /// certificate-backed (non-ad-hoc) signature and we're not inside a unit test.
    /// Tests use the file fallback so they never touch the developer's real keychain.
    static let usesKeychain: Bool = isRunningInTests ? false : hasStableCodeSignature

    /// True when this build cannot use the Keychain and keeps API keys in a
    /// clear-text local file instead, which Settings surfaces to the user.
    static var usesPlaintextFallback: Bool { !usesKeychain && !isRunningInTests }

    // MARK: - Primary API

    static func get(_ account: Account) -> String? {
        if usesKeychain {
            if let value = keychainGet(account) {
                return value
            }
            // One-time migration: pull any clear-text value left by a fallback-mode
            // build into the Keychain and scrub the clear-text copies.
            if let plaintext = fallbackValue(account) {
                if keychainSet(plaintext, account: account) {
                    clearFallbackCopies(account)
                }
                return plaintext
            }
            return nil
        }
        return fallbackValue(account)
    }

    @discardableResult
    static func set(_ value: String, account: Account) -> Bool {
        if usesKeychain {
            let ok = keychainSet(value, account: account)
            if ok {
                clearFallbackCopies(account)
            }
            return ok
        }
        fileStore.set(value, for: account.rawValue)
        removeDefaultsCopies(account)
        return true
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        if usesKeychain {
            keychainDelete(account)
        }
        clearFallbackCopies(account)
        return true
    }

    /// Load from stored value, or migrate once from this app's UserDefaults / legacy local build prefs.
    static func loadOrMigrate(
        account: Account,
        defaults: UserDefaults,
        legacyKey: String
    ) -> String {
        if let stored = get(account) {
            scrubLegacyCopies(defaults: defaults, legacyKey: legacyKey)
            return stored
        }

        let fromDefaults = defaults.string(forKey: legacyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Tests use an isolated defaults suite and temporary credential file; do not
        // let a developer's old local-build preferences leak into their expectations.
        let fromLegacyApp = isRunningInTests
            ? ""
            : preferenceValue(domain: legacyPreferenceDomain, key: legacyKey)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = !fromDefaults.isEmpty ? fromDefaults : fromLegacyApp

        // Only scrub once the value is safely somewhere else: a failed Keychain
        // write must not leave the user with no copy at all.
        if set(resolved, account: account), !resolved.isEmpty {
            scrubLegacyCopies(defaults: defaults, legacyKey: legacyKey)
        }
        return resolved
    }

    /// Older builds wrote the API key straight into the preferences plist, where it
    /// stayed readable through `defaults read` even after the key moved to the
    /// Keychain or the credential file. Drop those copies once they are redundant.
    private static func scrubLegacyCopies(defaults: UserDefaults, legacyKey: String) {
        if defaults.object(forKey: legacyKey) != nil {
            defaults.removeObject(forKey: legacyKey)
        }
        removeLegacyPreference(domain: legacyPreferenceDomain, key: legacyKey)
    }

    // MARK: - Non-secret string coalescing

    /// Non-secret string from this app's defaults, else previous OSS / local build prefs, else `fallback`.
    static func coalesceString(
        defaults: UserDefaults,
        key: String,
        fallback: String,
        persistLegacy: Bool = true
    ) -> String {
        if let local = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !local.isEmpty {
            return local
        }
        let domains = [legacyPreferenceDomain] + previousPreferenceDomains
        for domain in domains {
            let legacy = preferenceValue(domain: domain, key: key)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !legacy.isEmpty {
                if persistLegacy {
                    defaults.set(legacy, forKey: key)
                }
                return legacy
            }
        }
        return fallback
    }

    // MARK: - Signature inspection

    static let isRunningInTests: Bool =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil

    /// Ad-hoc signatures carry no certificate chain; anything with a leaf
    /// certificate has a designated requirement that survives rebuilds.
    private static var hasStableCodeSignature: Bool {
        var codeRef: SecCode?
        guard SecCodeCopySelf([], &codeRef) == errSecSuccess, let code = codeRef else {
            return false
        }
        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticRef) == errSecSuccess,
              let staticCode = staticRef else {
            return false
        }
        var infoRef: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else {
            return false
        }
        if let certificates = info[kSecCodeInfoCertificates as String] as? [AnyObject],
           !certificates.isEmpty {
            return true
        }
        return false
    }

    // MARK: - Keychain backend

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private static func keychainGet(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    @discardableResult
    private static func keychainSet(_ value: String, account: Account) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return keychainDelete(account)
        }
        guard let data = trimmed.data(using: .utf8) else { return false }
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess {
            return true
        }
        guard status == errSecItemNotFound else { return false }
        var add = baseQuery(account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Vibe Voice OSS"
        // Keep the secret unreadable while the machine is locked and out of iCloud.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        add[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecSuccess { return true }
        guard addStatus == errSecParam else { return false }
        // A file-based login keychain rejects the data-protection attributes.
        add.removeValue(forKey: kSecAttrAccessible as String)
        add.removeValue(forKey: kSecAttrSynchronizable as String)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    private static func keychainDelete(_ account: Account) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - Clear-text fallback backend

    private static var fileStore: CredentialFileStore { .shared }

    /// Value from the restricted credential file, migrating forward any clear-text
    /// copy left in the preferences plist by an older build and scrubbing it there.
    private static func fallbackValue(_ account: Account) -> String? {
        if let value = fileStore.value(for: account.rawValue) {
            return value
        }
        guard let legacy = legacyDefaultsValue(account) else { return nil }
        if !usesKeychain {
            fileStore.set(legacy, for: account.rawValue)
        }
        removeDefaultsCopies(account)
        return legacy
    }

    private static func clearFallbackCopies(_ account: Account) {
        fileStore.remove(account.rawValue)
        removeDefaultsCopies(account)
    }

    private static func defaultsKey(_ account: Account) -> String {
        "\(service).secure.\(account.rawValue)"
    }

    /// Every preference key a previous build may have written the secret to.
    private static func legacyDefaultsKeys(_ account: Account) -> [String] {
        let suffixes = [account.rawValue]
            + previousServices.map { "\($0).\(account.rawValue)" }
        return [defaultsKey(account)] + suffixes.map { "\(service).backup.\($0)" }
    }

    private static func legacyDefaultsValue(_ account: Account) -> String? {
        for key in legacyDefaultsKeys(account) {
            if let value = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    /// Scrub every clear-text preference copy once the value lives elsewhere.
    private static func removeDefaultsCopies(_ account: Account) {
        for key in legacyDefaultsKeys(account) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Drop a migrated secret from a preference domain an older build owned.
    /// Skipped under test: the suite runs against the developer's own preferences and
    /// has no business deleting what a real install of the legacy build put there.
    private static func removeLegacyPreference(domain: String, key: String) {
        guard !isRunningInTests else { return }
        guard CFPreferencesCopyAppValue(key as CFString, domain as CFString) != nil else { return }
        CFPreferencesSetAppValue(key as CFString, nil, domain as CFString)
        CFPreferencesAppSynchronize(domain as CFString)
    }

    private static func preferenceValue(domain: String, key: String) -> String {
        guard let raw = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else {
            return ""
        }
        if let string = raw as? String {
            return string
        }
        if let number = raw as? NSNumber {
            return number.stringValue
        }
        return ""
    }

    // MARK: - Legacy Keychain Cleanup

    /// Delete Keychain entries left over from pre-rename builds.
    ///
    /// Only the previous service names are purged. An earlier version also wiped the
    /// current service when running without a stable signature, on the theory that an
    /// ad-hoc build could not read those entries anyway — but the entries belong to
    /// the user's certificate-signed install, so running an ad-hoc build once
    /// destroyed the keys stored by the signed one.
    /// `SecItemDelete` does NOT trigger the login-password dialog — only reads do.
    static func cleanupLegacyKeychainEntries() {
        let doneKey = "\(service).keychain-cleanup-v4"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        for svc in previousServices {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
            ]
            SecItemDelete(query as CFDictionary)
        }
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
