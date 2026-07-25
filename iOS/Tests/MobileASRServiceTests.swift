import XCTest
@testable import VibeVoiceMobile

final class MobileASRServiceTests: XCTestCase {
    func testTooShortAudioFailsBeforeModelDownload() async {
        let service = MobileASRService()

        do {
            _ = try await service.transcribe(
                samples: [0, 0, 0],
                model: "tiny",
                mode: .original
            )
            XCTFail("Expected empty audio rejection")
        } catch let error as MobileASRError {
            XCTAssertEqual(error.localizedDescription, MobileASRError.emptyAudio.localizedDescription)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPolishedTextNormalizesWhitespaceAndPunctuation() {
        XCTAssertEqual(
            VoiceTextProcessor.process(" 你好   世界 ", mode: .polished),
            "你好 世界。"
        )
        XCTAssertEqual(
            VoiceTextProcessor.process("Already done!", mode: .polished),
            "Already done!"
        )
    }

    func testOriginalAndTranslateDoNotRewriteText() {
        XCTAssertEqual(VoiceTextProcessor.process("  raw text  ", mode: .original), "raw text")
        XCTAssertEqual(VoiceTextProcessor.process(" English result ", mode: .translate), "English result")
    }

    func testReleaseMemoryBeforePreparationIsSafe() async {
        let service = MobileASRService()
        await service.releaseMemory()
    }
}
