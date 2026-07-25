import Foundation
import WhisperKit

enum MobileASRError: LocalizedError {
    case emptyAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "没有录到可识别的声音。"
        case .emptyTranscript:
            return "模型没有返回文字，请靠近麦克风后重试。"
        }
    }
}

protocol MobileASRServing: Sendable {
    func prepare(model: String) async throws -> String
    func transcribe(samples: [Float], model: String, mode: VoiceOutputMode) async throws -> String
    func releaseMemory() async
}

extension MobileASRServing {
    func prepare() async throws -> String {
        try await prepare(model: MobileASRService.defaultModel)
    }

    func transcribe(samples: [Float], mode: VoiceOutputMode) async throws -> String {
        try await transcribe(samples: samples, model: MobileASRService.defaultModel, mode: mode)
    }
}

/// Owns the local model in the containing app process. The keyboard extension
/// never links or loads WhisperKit, keeping it within the extension memory cap.
actor MobileASRService: MobileASRServing {
    static let defaultModel = "tiny"

    private var whisperKit: WhisperKit?
    private var loadedModel = ""

    func prepare(model: String) async throws -> String {
        if whisperKit != nil, loadedModel == model {
            return "WhisperKit \(model) 已加载"
        }

        let configuration = WhisperKitConfig(
            model: model,
            verbose: false,
            prewarm: true,
            load: true,
            download: true,
            useBackgroundDownloadSession: true
        )
        let kit = try await WhisperKit(configuration)
        whisperKit = kit
        loadedModel = model
        return "WhisperKit \(model) 已预热"
    }

    func transcribe(samples: [Float], model: String, mode: VoiceOutputMode) async throws -> String {
        guard samples.count >= 1_600 else {
            throw MobileASRError.emptyAudio
        }
        if whisperKit == nil || loadedModel != model {
            _ = try await prepare(model: model)
        }
        guard let whisperKit else {
            throw MobileASRError.emptyTranscript
        }

        let options = DecodingOptions(
            task: mode == .translate ? .translate : .transcribe,
            usePrefillPrompt: true,
            detectLanguage: true,
            withoutTimestamps: true
        )
        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )
        let rawText = results
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            throw MobileASRError.emptyTranscript
        }
        return VoiceTextProcessor.process(rawText, mode: mode)
    }

    func releaseMemory() async {
        guard let whisperKit else { return }
        await whisperKit.unloadModels()
        self.whisperKit = nil
        loadedModel = ""
    }
}

enum VoiceTextProcessor {
    static func process(_ text: String, mode: VoiceOutputMode) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .polished else { return trimmed }

        let collapsed = trimmed
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\n+\s*"#, with: "\n", options: .regularExpression)
        guard let last = collapsed.last,
              !".!?。！？".contains(last) else {
            return collapsed
        }
        let containsCJK = collapsed.unicodeScalars.contains {
            (0x3400...0x9FFF).contains(Int($0.value))
        }
        return collapsed + (containsCJK ? "。" : ".")
    }
}
