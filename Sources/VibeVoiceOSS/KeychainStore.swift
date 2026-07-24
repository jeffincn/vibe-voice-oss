import Foundation
import Security

/// Stores API keys in the macOS Keychain when the app has a stable code-signing
/// identity, falling back to UserDefaults otherwise.
///
/// Keychain item ACLs are bound to the app's designated requirement. With a
/// persistent certificate (Apple Development / local self-signed, see
/// scripts/build-app.sh) the requirement survives rebuilds, so reads never
/// trigger the login-password dialog. Ad-hoc signatures change on every build
/// and would prompt each time, so those builds keep secrets in UserDefaults.
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
    /// Tests stay on UserDefaults so they never touch the developer's real keychain.
    static let usesKeychain: Bool = isRunningInTests ? false : hasStableCodeSignature

    // MARK: - Primary API

    static func get(_ account: Account) -> String? {
        if usesKeychain {
            if let value = keychainGet(account) {
                return value
            }
            // One-time migration: pull any plaintext value left by UserDefaults-era
            // builds into the Keychain and scrub the plaintext copy.
            if let plaintext = defaultsValue(account) {
                if keychainSet(plaintext, account: account) {
                    removeDefaultsCopies(account)
                }
                return plaintext
            }
            return nil
        }
        return defaultsValue(account)
    }

    @discardableResult
    static func set(_ value: String, account: Account) -> Bool {
        if usesKeychain {
            let ok = keychainSet(value, account: account)
            if ok {
                removeDefaultsCopies(account)
            }
            return ok
        }
        UserDefaults.standard.set(value, forKey: defaultsKey(account))
        return true
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        if usesKeychain {
            keychainDelete(account)
        }
        UserDefaults.standard.removeObject(forKey: defaultsKey(account))
        return true
    }

    /// Load from stored value, or migrate once from this app's UserDefaults / legacy local build prefs.
    static func loadOrMigrate(
        account: Account,
        defaults: UserDefaults,
        legacyKey: String
    ) -> String {
        if let stored = get(account) {
            return stored
        }

        let fromDefaults = defaults.string(forKey: legacyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fromLegacyApp = preferenceValue(domain: legacyPreferenceDomain, key: legacyKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = !fromDefaults.isEmpty ? fromDefaults : fromLegacyApp

        set(resolved, account: account)
        return resolved
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

    private static var isRunningInTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

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
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    private static func keychainDelete(_ account: Account) -> Bool {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - UserDefaults backend

    private static func defaultsKey(_ account: Account) -> String {
        "\(service).secure.\(account.rawValue)"
    }

    /// Current plaintext value, or one from keychain-era backup keys (migrating it forward).
    private static func defaultsValue(_ account: Account) -> String? {
        if let v = UserDefaults.standard.string(forKey: defaultsKey(account))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
            return v
        }
        for suffix in [account.rawValue] + previousServices.map({ "\($0).\(account.rawValue)" }) {
            let key = "\(service).backup.\(suffix)"
            if let v = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                if !usesKeychain {
                    UserDefaults.standard.set(v, forKey: defaultsKey(account))
                }
                return v
            }
        }
        return nil
    }

    /// Scrub every plaintext copy once the value is safely in the Keychain.
    private static func removeDefaultsCopies(_ account: Account) {
        UserDefaults.standard.removeObject(forKey: defaultsKey(account))
        for suffix in [account.rawValue] + previousServices.map({ "\($0).\(account.rawValue)" }) {
            UserDefaults.standard.removeObject(forKey: "\(service).backup.\(suffix)")
        }
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

    /// Delete Keychain entries left over from pre-rename builds. When the current
    /// build stores secrets in the Keychain itself, only the previous services are
    /// purged; UserDefaults-mode builds also clear the current service (reads by an
    /// ad-hoc build would prompt, so those entries are unusable anyway).
    /// `SecItemDelete` does NOT trigger the login-password dialog — only reads do.
    static func cleanupLegacyKeychainEntries() {
        let doneKey = usesKeychain
            ? "\(service).keychain-cleanup-v3-keychain"
            : "\(service).keychain-cleanup-v2"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let services = usesKeychain ? previousServices : [service] + previousServices
        for svc in services {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: svc,
            ]
            SecItemDelete(query as CFDictionary)
        }
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}
