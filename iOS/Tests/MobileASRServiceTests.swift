import XCTest
@testable import VibeVoiceMobile

final class MobileASRServiceTests: XCTestCase {
    func testTooShortAudioFailsBeforeModelDownload() async {
        let service = MobileASRService()

        do {
            _ = try await service.transcribe(samples: [0, 0, 0], model: "tiny")
            XCTFail("Expected empty audio rejection")
        } catch let error as MobileASRError {
            XCTAssertEqual(error.localizedDescription, MobileASRError.emptyAudio.localizedDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
