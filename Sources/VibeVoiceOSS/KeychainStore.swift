import Foundation
import Security

/// Stores API keys and non-secret preferences in UserDefaults.
///
/// Previously backed by the macOS Keychain (service: ``service``). With ad-hoc
/// or local-cert code signing the Keychain ACL changes on every rebuild and
/// triggers a login-password dialog. Since this is a local-only dev tool we
/// now keep everything in UserDefaults to avoid that prompt entirely. The
/// public API is unchanged so the rest of the codebase needs no edits.
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

    // MARK: - Primary API

    static func get(_ account: Account) -> String? {
        if let value = storedValue(account) {
            return value
        }
        // One-time migration from the old keychain-era UserDefaults backup key.
        for suffix in [account.rawValue] + previousServices.map({ "\($0).\(account.rawValue)" }) {
            let key = "\(service).backup.\(suffix)"
            if let v = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                set(v, account: account)
                return v
            }
        }
        return nil
    }

    @discardableResult
    static func set(_ value: String, account: Account) -> Bool {
        UserDefaults.standard.set(value, forKey: defaultsKey(account))
        return true
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
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

    // MARK: - Private

    private static func defaultsKey(_ account: Account) -> String {
        "\(service).secure.\(account.rawValue)"
    }

    private static func storedValue(_ account: Account) -> String? {
        guard let v = UserDefaults.standard.string(forKey: defaultsKey(account))?
            .trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
            return nil
        }
        return v
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

    /// Delete old Keychain entries left over from builds that used SecItem storage.
    /// `SecItemDelete` does NOT trigger the login-password dialog — only reads do.
    /// Called once on first launch after migration; the flag prevents repeat work.
    static func cleanupLegacyKeychainEntries() {
        let doneKey = "\(service).keychain-cleanup-v2"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let services = [service] + previousServices
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
