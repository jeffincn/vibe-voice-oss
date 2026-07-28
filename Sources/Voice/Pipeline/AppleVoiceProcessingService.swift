import AVFoundation
import Foundation

/// Enables Apple Voice Processing (NS / AEC / AGC) when supported, with graceful fallback.
final class AppleVoiceProcessingService: @unchecked Sendable {
    private(set) var isEnabled = false
    private(set) var lastErrorDescription: String?

    @discardableResult
    func enable(on inputNode: AVAudioInputNode) -> Bool {
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            isEnabled = true
            lastErrorDescription = nil
            SpeechPipelineLog.voiceProcessing.info("Voice Processing enabled")
            return true
        } catch {
            isEnabled = false
            lastErrorDescription = error.localizedDescription
            SpeechPipelineLog.voiceProcessing.error(
                "Voice Processing unavailable: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    func disable(on inputNode: AVAudioInputNode) {
        guard isEnabled else { return }
        do {
            try inputNode.setVoiceProcessingEnabled(false)
        } catch {
            SpeechPipelineLog.voiceProcessing.error(
                "Failed to disable Voice Processing: \(error.localizedDescription, privacy: .public)"
            )
        }
        isEnabled = false
    }
}
