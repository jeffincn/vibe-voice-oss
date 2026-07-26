import XCTest
@testable import VibeVoiceMobile

final class VoiceBridgeTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceBridgeTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRequestPublishAndConsumeLifecycle() {
        let bridge = VoiceBridgeStore(directory: directory)
        let field = UUID()

        let request = bridge.request(mode: .translate, documentID: field)
        XCTAssertEqual(request.status, .requested)
        XCTAssertEqual(request.mode, .translate)
        XCTAssertEqual(request.targetDocumentID, field)

        bridge.setMode(.original)
        XCTAssertEqual(bridge.load().mode, .original)

        bridge.publish(status: .ready, text: "Hello", message: "可插入")
        XCTAssertEqual(bridge.load().text, "Hello")

        bridge.markConsumed(requestID: request.requestID)
        XCTAssertEqual(bridge.load().status, .consumed)
    }

    func testConsumingClearsTheTranscriptFromSharedStorage() {
        let bridge = VoiceBridgeStore(directory: directory)
        let request = bridge.request(mode: .original, documentID: UUID())
        bridge.publish(status: .ready, text: "机密内容")

        bridge.markConsumed(requestID: request.requestID)

        let state = bridge.load()
        XCTAssertTrue(state.text.isEmpty)
        XCTAssertNil(state.targetDocumentID)
        XCTAssertFalse(state.hasFreshResult())
    }

    func testResultIsOnlyTargetedAtTheRequestingField() {
        let bridge = VoiceBridgeStore(directory: directory)
        let requestingField = UUID()
        bridge.request(mode: .original, documentID: requestingField)
        bridge.publish(status: .ready, text: "你好")

        let state = bridge.load()
        XCTAssertTrue(state.hasFreshResult())
        XCTAssertTrue(state.targets(documentID: requestingField))
        XCTAssertFalse(state.targets(documentID: UUID()))
        XCTAssertFalse(state.targets(documentID: nil))
    }

    func testStaleResultIsNoLongerFresh() {
        var state = VoiceBridgeState.idle
        state.status = .ready
        state.text = "你好"
        state.updatedAt = Date()

        XCTAssertTrue(state.hasFreshResult())
        XCTAssertFalse(
            state.hasFreshResult(
                now: state.updatedAt.addingTimeInterval(VoiceBridgeState.readyLifetime + 1)
            )
        )
    }

    func testSeparateStoreInstancesShareStateThroughTheContainer() {
        let writer = VoiceBridgeStore(directory: directory)
        let reader = VoiceBridgeStore(directory: directory)

        let request = writer.request(mode: .polished, documentID: UUID())
        writer.publish(status: .ready, text: "跨进程")

        let observed = reader.load()
        XCTAssertEqual(observed.requestID, request.requestID)
        XCTAssertEqual(observed.text, "跨进程")
    }

    func testInterruptedRecordingRecoversToActionableFailure() {
        let bridge = VoiceBridgeStore(directory: directory)
        bridge.request(mode: .polished, documentID: UUID())
        bridge.publish(status: .recording, message: "正在录音")

        XCTAssertTrue(bridge.recoverInterruptedWork())
        XCTAssertEqual(bridge.load().status, .failed)
        XCTAssertTrue(bridge.load().message.contains("重新录音"))
        XCTAssertFalse(bridge.recoverInterruptedWork())
    }
}
