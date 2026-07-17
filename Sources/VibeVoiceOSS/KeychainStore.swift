import Foundation
import Security

/// Stores secrets in the macOS Keychain. Never write API keys to UserDefaults.
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

    static func get(_ account: Account) -> String? {
        if let value = get(account, service: service) {
            return value
        }
        for previous in previousServices {
            if let value = get(account, service: previous) {
                set(value, account: account)
                return value
            }
        }
        return nil
    }

    private static func get(_ account: Account, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func set(_ value: String, account: Account) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Load from Keychain, or migrate once from this app's UserDefaults / legacy local build prefs.
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
        if !fromDefaults.isEmpty {
            defaults.removeObject(forKey: legacyKey)
        }
        return resolved
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
}
