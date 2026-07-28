import XCTest
@testable import VibeVoiceOSS

/// Under test `usesKeychain` is forced off, so these exercise the credential-file
/// backend and the migration paths — never the developer's real keychain.
final class KeychainStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "KeychainStoreTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        clearStoredSecrets()
    }

    override func tearDownWithError() throws {
        clearStoredSecrets()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    private func clearStoredSecrets() {
        KeychainStore.delete(.asrAPIKey)
        KeychainStore.delete(.llmAPIKey)
    }

    // MARK: - Backend selection

    func testTestsNeverTouchTheKeychainAndAreNotWarnedAboutPlaintext() {
        XCTAssertTrue(KeychainStore.isRunningInTests)
        XCTAssertFalse(KeychainStore.usesKeychain)
        // The Settings warning is for real ad-hoc builds, not the test runner.
        XCTAssertFalse(KeychainStore.usesPlaintextFallback)
    }

    // MARK: - Round trip

    func testSetGetDelete() {
        XCTAssertNil(KeychainStore.get(.asrAPIKey))

        XCTAssertTrue(KeychainStore.set("sk-asr", account: .asrAPIKey))
        XCTAssertEqual(KeychainStore.get(.asrAPIKey), "sk-asr")
        XCTAssertNil(KeychainStore.get(.llmAPIKey), "accounts must not share a slot")

        KeychainStore.delete(.asrAPIKey)
        XCTAssertNil(KeychainStore.get(.asrAPIKey))
    }

    func testStoringABlankValueClearsTheSecret() {
        KeychainStore.set("sk-asr", account: .asrAPIKey)
        KeychainStore.set("   ", account: .asrAPIKey)
        XCTAssertNil(KeychainStore.get(.asrAPIKey))
    }

    // MARK: - Migration

    func testMigratesTheLegacyDefaultsValueAndRemovesTheClearTextCopy() {
        defaults.set("sk-from-prefs", forKey: "apiKey")

        let resolved = KeychainStore.loadOrMigrate(
            account: .asrAPIKey, defaults: defaults, legacyKey: "apiKey"
        )

        XCTAssertEqual(resolved, "sk-from-prefs")
        XCTAssertEqual(KeychainStore.get(.asrAPIKey), "sk-from-prefs")
        XCTAssertNil(
            defaults.string(forKey: "apiKey"),
            "a migrated key left in the plist stays readable through `defaults read`"
        )
    }

    func testMigrationTrimsWhitespacePastedWithTheKey() {
        defaults.set("  sk-padded\n", forKey: "apiKey")

        let resolved = KeychainStore.loadOrMigrate(
            account: .asrAPIKey, defaults: defaults, legacyKey: "apiKey"
        )

        XCTAssertEqual(resolved, "sk-padded")
    }

    func testAnAlreadyStoredKeyWinsAndStillClearsAStaleClearTextCopy() {
        KeychainStore.set("sk-current", account: .asrAPIKey)
        defaults.set("sk-stale", forKey: "apiKey")

        let resolved = KeychainStore.loadOrMigrate(
            account: .asrAPIKey, defaults: defaults, legacyKey: "apiKey"
        )

        XCTAssertEqual(resolved, "sk-current")
        XCTAssertNil(defaults.string(forKey: "apiKey"))
    }

    func testMigratingWithNothingStoredAnywhereYieldsAnEmptyKey() {
        let resolved = KeychainStore.loadOrMigrate(
            account: .llmAPIKey, defaults: defaults, legacyKey: "llmApiKey"
        )

        XCTAssertEqual(resolved, "")
        XCTAssertNil(KeychainStore.get(.llmAPIKey))
    }

    /// Builds before the credential file wrote secrets to `<service>.secure.<account>`
    /// in the standard defaults. Reading the account has to pull those forward and
    /// scrub them, otherwise the clear-text copy outlives the migration.
    func testSecretsLeftInTheStandardDefaultsAreMigratedForwardAndScrubbed() throws {
        let key = "\(KeychainStore.service).secure.asr.apiKey"
        UserDefaults.standard.set("sk-legacy-defaults", forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        XCTAssertEqual(KeychainStore.get(.asrAPIKey), "sk-legacy-defaults")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: key),
            "the clear-text preference copy should be gone once the value is stored"
        )
        XCTAssertEqual(KeychainStore.get(.asrAPIKey), "sk-legacy-defaults")
    }

    // MARK: - Non-secret coalescing

    func testCoalesceStringPrefersTheLocalValue() {
        defaults.set("  local  ", forKey: "inputDeviceUID")
        XCTAssertEqual(
            KeychainStore.coalesceString(defaults: defaults, key: "inputDeviceUID", fallback: "fb"),
            "local"
        )
    }

    func testCoalesceStringFallsBackWhenTheLocalValueIsBlank() {
        defaults.set("   ", forKey: "inputDeviceUID")
        XCTAssertEqual(
            KeychainStore.coalesceString(defaults: defaults, key: "inputDeviceUID", fallback: "fb"),
            "fb"
        )
    }

    func testCoalesceStringFallsBackWhenNothingIsStored() {
        XCTAssertEqual(
            KeychainStore.coalesceString(defaults: defaults, key: "unset-key", fallback: "fb"),
            "fb"
        )
    }
}
