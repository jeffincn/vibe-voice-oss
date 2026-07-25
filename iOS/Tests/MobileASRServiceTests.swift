import Darwin
import XCTest
import WhisperKit
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

    func testWhisperTinyDownloadsAndTranscribesChineseFixture() async throws {
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "asr_hello", withExtension: "wav")
        )
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: fixture.path)
        let service = MobileASRService()
        let startedAt = Date()
        let memoryBefore = Self.residentMemoryBytes()
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue

        let modelStatus = try await service.prepare(model: MobileASRService.defaultModel)
        let transcript = try await service.transcribe(
            samples: samples,
            model: MobileASRService.defaultModel,
            mode: .original
        )
        let translation = try await service.transcribe(
            samples: samples,
            model: MobileASRService.defaultModel,
            mode: .translate
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        let memoryLoaded = Self.residentMemoryBytes()

        XCTAssertTrue(modelStatus.contains("WhisperKit"))
        XCTAssertFalse(transcript.isEmpty)
        XCTAssertFalse(translation.isEmpty)
        print(
            "MODEL_INTEGRATION transcript=\(transcript) " +
            "translation=\(translation) elapsed=\(elapsed) " +
            "residentBefore=\(memoryBefore) residentLoaded=\(memoryLoaded) " +
            "thermalBefore=\(thermalBefore) " +
            "thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue)"
        )
        await service.releaseMemory()
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }
}
