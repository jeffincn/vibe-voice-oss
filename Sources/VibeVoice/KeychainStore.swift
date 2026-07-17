import Foundation
import Security

/// Stores secrets in the macOS Keychain. Never write API keys to UserDefaults.
enum KeychainStore {
    static let service = "app.vibevoice.macos"

    enum Account: String {
        case asrAPIKey = "asr.apiKey"
        case llmAPIKey = "llm.apiKey"
    }

    static func get(_ account: Account) -> String? {
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
        return value
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

    /// Load from Keychain, or migrate once from UserDefaults plaintext and scrub it.
    static func loadOrMigrate(
        account: Account,
        defaults: UserDefaults,
        legacyKey: String
    ) -> String {
        if let stored = get(account) {
            return stored
        }
        let legacy = defaults.string(forKey: legacyKey) ?? ""
        if !legacy.isEmpty {
            set(legacy, account: account)
        } else {
            set("", account: account)
        }
        defaults.removeObject(forKey: legacyKey)
        return legacy
    }
}
