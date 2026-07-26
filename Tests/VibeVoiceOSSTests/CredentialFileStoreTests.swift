import XCTest
@testable import VibeVoiceOSS

final class CredentialFileStoreTests: XCTestCase {
    private var directory: URL!
    private var store: CredentialFileStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CredentialFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = CredentialFileStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        store = nil
        directory = nil
        try super.tearDownWithError()
    }

    private var fileURL: URL {
        directory.appendingPathComponent("credentials.json", isDirectory: false)
    }

    private func mode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }

    func testRoundTripsValues() {
        XCTAssertNil(store.value(for: "asr.apiKey"))

        store.set("sk-asr", for: "asr.apiKey")
        store.set("sk-llm", for: "llm.apiKey")

        XCTAssertEqual(store.value(for: "asr.apiKey"), "sk-asr")
        XCTAssertEqual(store.value(for: "llm.apiKey"), "sk-llm")
    }

    func testValuesSurviveANewStoreOverTheSameDirectory() {
        store.set("sk-asr", for: "asr.apiKey")

        let reopened = CredentialFileStore(directory: directory)
        XCTAssertEqual(reopened.value(for: "asr.apiKey"), "sk-asr")
    }

    func testWhitespaceIsTrimmedAndBlankValuesRemoveTheEntry() {
        store.set("  sk-asr\n", for: "asr.apiKey")
        XCTAssertEqual(store.value(for: "asr.apiKey"), "sk-asr")

        store.set("   ", for: "asr.apiKey")
        XCTAssertNil(store.value(for: "asr.apiKey"))
    }

    func testRemovingTheLastEntryDeletesTheFile() {
        store.set("sk-asr", for: "asr.apiKey")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.remove("asr.apiKey")

        XCTAssertNil(store.value(for: "asr.apiKey"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fileURL.path),
            "an empty credential file should not linger on disk"
        )
    }

    func testRemovingOneAccountKeepsTheOther() {
        store.set("sk-asr", for: "asr.apiKey")
        store.set("sk-llm", for: "llm.apiKey")

        store.remove("asr.apiKey")

        XCTAssertNil(store.value(for: "asr.apiKey"))
        XCTAssertEqual(store.value(for: "llm.apiKey"), "sk-llm")
    }

    func testSecretsAreNotReadableByOtherUsers() throws {
        store.set("sk-asr", for: "asr.apiKey")

        XCTAssertEqual(try mode(of: fileURL), 0o600)
        XCTAssertEqual(try mode(of: directory), 0o700)
    }

    func testPermissionsAreReappliedAfterRewrites() throws {
        store.set("sk-asr", for: "asr.apiKey")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: fileURL.path
        )

        store.set("sk-rotated", for: "asr.apiKey")

        XCTAssertEqual(store.value(for: "asr.apiKey"), "sk-rotated")
        XCTAssertEqual(try mode(of: fileURL), 0o600)
    }

    func testCorruptedFileIsTreatedAsEmptyRatherThanCrashing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        XCTAssertNil(store.value(for: "asr.apiKey"))

        store.set("sk-asr", for: "asr.apiKey")
        XCTAssertEqual(store.value(for: "asr.apiKey"), "sk-asr")
    }
}
