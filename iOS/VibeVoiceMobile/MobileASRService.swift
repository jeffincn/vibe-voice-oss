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
    func transcribe(samples: [Float], model: String) async throws -> String
}

extension MobileASRServing {
    func prepare() async throws -> String {
        try await prepare(model: MobileASRService.defaultModel)
    }

    func transcribe(samples: [Float]) async throws -> String {
        try await transcribe(samples: samples, model: MobileASRService.defaultModel)
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

    func transcribe(samples: [Float], model: String) async throws -> String {
        guard samples.count >= 1_600 else {
            throw MobileASRError.emptyAudio
        }
        if whisperKit == nil || loadedModel != model {
            _ = try await prepare(model: model)
        }
        guard let whisperKit else {
            throw MobileASRError.emptyTranscript
        }

        let results = try await whisperKit.transcribe(audioArray: samples)
        let text = results
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw MobileASRError.emptyTranscript
        }
        return text
    }
}
