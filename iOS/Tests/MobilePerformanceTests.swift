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
            performMaintenance: true,
            fullCheck: true
        )

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<50 {
                "nihao".forEach { engine.process(letter: $0) }
                _ = engine.commitBestCandidate()
            }
        }
    }

    func testBridgeRoundTripLatency() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceBridgePerf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bridge = VoiceBridgeStore(directory: directory)
        let field = UUID()

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            for _ in 0..<100 {
                let request = bridge.request(mode: .original, documentID: field)
                bridge.publish(status: .ready, text: "hello")
                bridge.markConsumed(requestID: request.requestID)
            }
        }
    }
}
