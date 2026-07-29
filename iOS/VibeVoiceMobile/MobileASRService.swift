import Foundation
import WhisperKit

enum MobileASRError: LocalizedError {
    case emptyAudio
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return MobileL10n.t(.asrNoAudio)
        case .emptyTranscript:
            return MobileL10n.t(.asrNoText)
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
            return MobileL10n.t(.asrModelLoaded, model)
        }

        let configuration = WhisperKitConfig(
            model: model,
            verbose: false,
            prewarm: true,
            load: true,
            download: true,
            useBackgroundDownloadSession: true
        )
        // A cold prepare downloads and compiles; a warm one does not. Only the
        // elapsed time separates "the model is slow" from "the model is being
        // fetched again", and on a device those look identical from the UI.
        let started = Date()
        do {
            let kit = try await WhisperKit(configuration)
            whisperKit = kit
            loadedModel = model
            MobileLog.info(.model, "prepare.succeeded", [
                "model": model,
                "ms": String(Int(Date().timeIntervalSince(started) * 1000)),
            ])
            return MobileL10n.t(.asrModelWarmed, model)
        } catch {
            MobileLog.error(.model, "prepare.failed", [
                "model": model,
                "ms": String(Int(Date().timeIntervalSince(started) * 1000)),
                "error": error.localizedDescription,
            ])
            throw error
        }
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
        let started = Date()
        let results = try await whisperKit.transcribe(
            audioArray: samples,
            decodeOptions: options
        )
        let rawText = results
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let processed = rawText.isEmpty ? "" : VoiceTextProcessor.process(rawText, mode: mode)
        MobileLog.emit(
            .model,
            "transcribe.finished",
            level: rawText.isEmpty ? .error : .info,
            [
                "model": model,
                "mode": mode.rawValue,
                // 16 kHz mono, so this doubles as the recording length.
                "audioMs": String(samples.count / 16),
                "ms": String(Int(Date().timeIntervalSince(started) * 1000)),
                "raw": MobileLog.fingerprint(rawText),
                "processed": MobileLog.fingerprint(processed),
            ]
        )
        guard !rawText.isEmpty else {
            throw MobileASRError.emptyTranscript
        }
        return processed
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
