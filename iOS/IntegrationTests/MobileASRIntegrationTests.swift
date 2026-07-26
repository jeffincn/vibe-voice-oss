import Darwin
import XCTest
import WhisperKit
@testable import VibeVoiceMobile

/// Exercises the real WhisperKit model end to end.
///
/// Kept out of `VibeVoiceMobileTests` because it downloads roughly 73 MB from
/// Hugging Face on a cold machine: putting it in the default suite makes every
/// run depend on the network and turns a rate-limited or offline machine into a
/// test failure nobody can act on. Run it with the `VibeVoiceMobileIntegration`
/// scheme; `scripts/test-ios-device.sh` always does, because the physical
/// device gate is only meaningful against the real model.
final class MobileASRIntegrationTests: XCTestCase {
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
