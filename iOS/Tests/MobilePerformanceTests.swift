import XCTest
@testable import VibeVoiceMobile

final class MobilePerformanceTests: XCTestCase {
    func testRimeSessionAndCandidateLatency() throws {
        let userDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VibeVoiceRimePerf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: userDirectory) }
        let engine = try RimeEngineFactory.make(
            bundle: .main,
            userDataDirectory: userDirectory,
            performMaintenance: true
        )

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<50 {
                "nihao".forEach { engine.process(letter: $0) }
                _ = engine.commitBestCandidate()
            }
        }
    }

    func testBridgeRoundTripLatency() throws {
        let suite = "VoiceBridgePerfTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let bridge = VoiceBridgeStore(defaults: defaults)

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 {
                let request = bridge.request(mode: .original)
                bridge.publish(status: .ready, text: "hello")
                bridge.markConsumed(requestID: request.requestID)
            }
        }
    }
}
