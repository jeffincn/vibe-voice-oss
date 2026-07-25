import XCTest
@testable import VibeVoiceMobile

final class VoiceBridgeTests: XCTestCase {
    func testRequestPublishAndConsumeLifecycle() throws {
        let suite = "VoiceBridgeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let bridge = VoiceBridgeStore(defaults: defaults)

        let request = bridge.request(mode: .translate)
        XCTAssertEqual(request.status, .requested)
        XCTAssertEqual(request.mode, .translate)

        bridge.publish(status: .ready, text: "Hello", message: "可插入")
        XCTAssertEqual(bridge.load().text, "Hello")

        bridge.markConsumed(requestID: request.requestID)
        XCTAssertEqual(bridge.load().status, .consumed)
    }
}
