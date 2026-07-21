import Foundation

struct PipelineASRResult: Sendable {
    let text: String
    let language: String?
    let audioDuration: Double
    let inferenceLatency: Double
}

enum PipelineASRServiceError: LocalizedError {
    case apiBackendUnsupported
    case emptyText
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .apiBackendUnsupported:
            "Voice Pipeline 仅支持本地 ASR（WhisperKit 或 Qwen3-ASR），请将 ASR 模式设为「集成」。"
        case .emptyText:
            "本地 ASR 未返回文本。"
        case let .notReady(message):
            message
        }
    }
}

/// Segment-level batch ASR for Voice Pipeline (Qwen samples API or WhisperKit via WAV).
actor PipelineASRService {
    func prepare(configuration: TranscriptionConfiguration) async throws {
        guard configuration.backend == .integrated else {
            throw PipelineASRServiceError.apiBackendUnsupported
        }
        try await NativeASRClient.shared.checkRuntime(configuration: configuration)
    }

    func transcribe(
        samples: [Float],
        configuration: TranscriptionConfiguration
    ) async throws -> PipelineASRResult {
        guard configuration.backend == .integrated else {
            throw PipelineASRServiceError.apiBackendUnsupported
        }
        let started = CFAbsoluteTimeGetCurrent()
        let audioDuration = Double(samples.count) / 16_000.0

        let text: String
        let language: String?
        switch configuration.integratedEngine {
        case .qwen3MLX:
            let sampleResult = try await NativeASRClient.shared.transcribe(
                samples: samples,
                configuration: configuration
            )
            text = sampleResult.text
            language = sampleResult.language
        case .whisperMLX:
            let wav = WAVEncoder.encode(samples: samples, inputSampleRate: 16_000)
            text = try await NativeASRClient.shared.transcribe(wav: wav, configuration: configuration)
            language = configuration.language
        }

        let latency = CFAbsoluteTimeGetCurrent() - started
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PipelineASRServiceError.emptyText }
        SpeechPipelineLog.asr.info(
            "asr done duration=\(audioDuration, format: .fixed(precision: 2))s latency=\(latency, format: .fixed(precision: 2))s chars=\(trimmed.count)"
        )
        return PipelineASRResult(
            text: trimmed,
            language: language,
            audioDuration: audioDuration,
            inferenceLatency: latency
        )
    }
}
