import CoreML
import Foundation

enum VADEvent: Equatable, Sendable {
    case speechStarted
    case speechActive
    case speechEnded
    case silence
}

struct VADResult: Sendable {
    let event: VADEvent
    let speechProbability: Float
}

enum VADServiceError: LocalizedError {
    case modelMissing(path: String)
    case modelLoadFailed(String)

    var errorDescription: String? {
        switch self {
        case let .modelMissing(path):
            "Silero VAD 模型未准备：\(path)。请运行 scripts/prepare-silero-vad.sh。"
        case let .modelLoadFailed(message):
            "Silero VAD 加载失败：\(message)"
        }
    }
}

struct VADConfig: Sendable {
    var speechThreshold: Float = 0.45
    var silenceThreshold: Float = 0.28
    /// Silero window size at 16 kHz.
    var windowSamples: Int = 512
    var sampleRate: Int = 16_000
}

/// Prefer CoreML when `~/Documents/VibeVoiceOSS/Models/SileroVAD/silero_vad.mlmodelc` exists.
final class VADService: @unchecked Sendable {
    private let config: VADConfig
    private let lock = NSLock()
    private var pending: [Float] = []
    private var wasSpeech = false
    private var model: MLModel?
    private(set) var usesCoreML = false
    private(set) var modelDirectory: URL

    static var defaultModelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VibeVoiceOSS/Models/SileroVAD", isDirectory: true)
    }

    init(config: VADConfig = VADConfig(), modelDirectory: URL = VADService.defaultModelDirectory) {
        self.config = config
        self.modelDirectory = modelDirectory
    }

    /// Load CoreML Silero, or bootstrap the Silero-windowed energy backend when CoreML is absent.
    func load() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let compiled = modelDirectory.appendingPathComponent("silero_vad.mlmodelc", isDirectory: true)
        let package = modelDirectory.appendingPathComponent("silero_vad.mlpackage", isDirectory: true)
        let marker = modelDirectory.appendingPathComponent("USE_ENERGY_VAD")

        if fm.fileExists(atPath: compiled.path) || fm.fileExists(atPath: package.path) {
            let url: URL
            if fm.fileExists(atPath: compiled.path) {
                url = compiled
            } else {
                url = try MLModel.compileModel(at: package)
            }
            do {
                model = try MLModel(contentsOf: url)
                usesCoreML = true
                if fm.fileExists(atPath: marker.path) {
                    try? fm.removeItem(at: marker)
                }
                SpeechPipelineLog.vad.info("Loaded Silero CoreML from \(url.path, privacy: .public)")
                return
            } catch {
                SpeechPipelineLog.vad.error(
                    "CoreML load failed, falling back to energy VAD: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        if !fm.fileExists(atPath: marker.path) {
            try "energy\n".write(to: marker, atomically: true, encoding: .utf8)
        }
        model = nil
        usesCoreML = false
        SpeechPipelineLog.vad.warning(
            "Using energy VAD backend (run scripts/prepare-silero-vad.sh for CoreML Silero)"
        )
    }

    func reset() {
        lock.withLock {
            pending.removeAll(keepingCapacity: true)
            wasSpeech = false
        }
    }

    /// Push 16 kHz mono samples; returns the latest VAD result for the most recent full window.
    func push(_ samples: [Float]) -> VADResult? {
        guard !samples.isEmpty else { return nil }
        return lock.withLock {
            pending.append(contentsOf: samples)
            var last: VADResult?
            while pending.count >= config.windowSamples {
                let window = Array(pending.prefix(config.windowSamples))
                pending.removeFirst(config.windowSamples)
                let probability = inferProbability(window)
                let result = classify(probability: probability)
                last = result
                SpeechPipelineLog.vad.debug(
                    "p=\(probability, format: .fixed(precision: 3)) event=\(String(describing: result.event), privacy: .public)"
                )
            }
            return last
        }
    }

    private func inferProbability(_ window: [Float]) -> Float {
        if usesCoreML, let model {
            if let p = inferCoreML(model: model, window: window) {
                return p
            }
        }
        return energyProbability(window)
    }

    private func inferCoreML(model: MLModel, window: [Float]) -> Float? {
        do {
            let inputName = model.modelDescription.inputDescriptionsByName.keys.sorted().first ?? "audio"
            let array = try MLMultiArray(shape: [1, NSNumber(value: window.count)], dataType: .float32)
            for (index, sample) in window.enumerated() {
                array[index] = NSNumber(value: sample)
            }
            let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: array)])
            let out = try model.prediction(from: provider)
            // Prefer common Silero output names.
            let candidates = ["output", "probability", "speech_prob", "var_1093"]
            for name in candidates {
                if let value = out.featureValue(for: name)?.multiArrayValue {
                    return Float(truncating: value[0])
                }
                if let value = out.featureValue(for: name)?.doubleValue {
                    return Float(value)
                }
            }
            // Fallback: first multiarray / double output feature.
            for name in out.featureNames {
                if let array = out.featureValue(for: name)?.multiArrayValue {
                    return Float(truncating: array[0])
                }
                if let value = out.featureValue(for: name)?.doubleValue {
                    return Float(value)
                }
            }
            return nil
        } catch {
            SpeechPipelineLog.vad.error("CoreML infer failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Energy + zero-crossing heuristic approximating speech probability for Silero-sized windows.
    private func energyProbability(_ window: [Float]) -> Float {
        guard !window.isEmpty else { return 0 }
        let meanSquare = window.reduce(Float.zero) { $0 + $1 * $1 } / Float(window.count)
        let rms = sqrt(meanSquare)
        let db = 20 * log10(max(rms, 1e-6))
        // Quieter mics / Voice Processing: map roughly -55…-12 dBFS → 0…1
        let energyScore = max(0, min(1, (db + 55) / 43))

        var crossings = 0
        for index in 1..<window.count {
            if (window[index - 1] >= 0) != (window[index] >= 0) {
                crossings += 1
            }
        }
        let zcr = Float(crossings) / Float(window.count)
        // Ignore clicky / very tonal noise; keep speech ZCR band.
        let zcrPenalty: Float
        if zcr > 0.35 {
            zcrPenalty = 0.45
        } else if zcr < 0.01 {
            zcrPenalty = 0.2
        } else {
            zcrPenalty = 0
        }
        return max(0, min(1, energyScore - zcrPenalty))
    }

    private func classify(probability: Float) -> VADResult {
        let speaking = probability >= config.speechThreshold
        let silent = probability <= config.silenceThreshold
        let event: VADEvent
        if speaking {
            event = wasSpeech ? .speechActive : .speechStarted
            wasSpeech = true
        } else if silent {
            event = wasSpeech ? .speechEnded : .silence
            wasSpeech = false
        } else {
            event = wasSpeech ? .speechActive : .silence
        }
        return VADResult(event: event, speechProbability: probability)
    }
}
