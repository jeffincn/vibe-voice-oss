import Foundation
import Testing
@testable import VibeVoiceInputShared

struct InputMethodBridgeTests {
    @Test func roundTripsStateWithRestrictedFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibevoice-bridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InputMethodBridgeStore(directory: directory)
        let requested = store.request(mode: .conversation)
        let loaded = try #require(store.load())
        #expect(loaded.requestID == requested.requestID)
        #expect(loaded.status == .requested)
        let ready = store.update(.ready, from: loaded, text: "你好")
        #expect(store.load()?.isFresh() == true)
        #expect(ready.text == "你好")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
    }

    @Test func staleWorkIsRecoveredAsFailed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vibevoice-bridge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = InputMethodBridgeStore(directory: directory)
        var state = store.request()
        state.updatedAt = Date(timeIntervalSinceNow: -301)
        _ = store.write(state)
        let recovered = try #require(store.recoverInterruptedWork())
        #expect(recovered.status == .failed)
    }
}
