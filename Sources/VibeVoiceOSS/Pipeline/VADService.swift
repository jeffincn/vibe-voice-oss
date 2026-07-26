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
    var speechThreshold: Float = 0.35
    var silenceThreshold: Float = 0.20
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

    // Silero v5 recurrent state (LSTM h/c) + 64-sample context carried across 512-sample chunks.
    private static let contextSamples = 64
    private static let chunkSamples = 512
    private var sileroContext = [Float](repeating: 0, count: VADService.contextSamples)
    private var sileroH: MLMultiArray?
    private var sileroC: MLMultiArray?

    enum Backend {
        case sileroCoreML
        /// Windowed short-term energy. Far weaker than Silero: music, keyboard noise
        /// and fan hum all read as speech.
        case energy
    }

    static var defaultModelDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/VibeVoiceOSS/Models/SileroVAD", isDirectory: true)
    }

    /// Which backend `load()` would pick, without loading anything, so Settings can
    /// tell the user they are on the degraded detector before a session starts.
    static func availableBackend(in directory: URL = VADService.defaultModelDirectory) -> Backend {
        let manager = FileManager.default
        let compiled = directory.appendingPathComponent("silero_vad.mlmodelc", isDirectory: true)
        let package = directory.appendingPathComponent("silero_vad.mlpackage", isDirectory: true)
        let hasModel = manager.fileExists(atPath: compiled.path)
            || manager.fileExists(atPath: package.path)
        return hasModel ? .sileroCoreML : .energy
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
                resetSileroStateLocked()
                if fm.fileExists(atPath: marker.path) {
                    try? fm.removeItem(at: marker)
                }
                SpeechPipelineLog.vad.info(
                    "Loaded Silero CoreML from \(url.path, privacy: .public) h=\(self.sileroH != nil) c=\(self.sileroC != nil)"
                )
                return
            } catch {
                SpeechPipelineLog.vad.error(
                    "CoreML load failed, falling back to energy VAD: \(error.localizedDescription, privacy: .public)"
                )
            }
        } else {
            SpeechPipelineLog.vad.warning(
                "Silero mlmodelc missing at \(compiled.path, privacy: .public)"
            )
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
            sileroContext = [Float](repeating: 0, count: VADService.contextSamples)
            resetSileroStateLocked()
        }
    }

    private func resetSileroStateLocked() {
        guard usesCoreML else {
            sileroH = nil
            sileroC = nil
            return
        }
        sileroH = try? MLMultiArray(shape: [1, 1, 128], dataType: .float16)
        sileroC = try? MLMultiArray(shape: [1, 1, 128], dataType: .float16)
        zeroFill(sileroH)
        zeroFill(sileroC)
    }

    private func zeroFill(_ array: MLMultiArray?) {
        guard let array else { return }
        let count = array.count
        let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: count)
        for index in 0..<count { ptr[index] = 0 }
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
        let energy = energyProbability(window)
        if usesCoreML, let model {
            if let silero = inferSilero(model: model, chunk: window) {
                // Prefer Silero; keep a small energy floor so quiet speech still endpoints.
                return max(silero, energy * 0.85)
            }
            SpeechPipelineLog.vad.error("Silero infer returned nil; using energy=\(energy, format: .fixed(precision: 3))")
        }
        return energy
    }

    /// Silero v5 CoreML: audio=[64 context + 512 chunk], carrying LSTM h/c across calls.
    private func inferSilero(model: MLModel, chunk: [Float]) -> Float? {
        guard chunk.count == VADService.chunkSamples else { return nil }
        if sileroH == nil || sileroC == nil {
            resetSileroStateLocked()
        }
        guard let h = sileroH, let c = sileroC else {
            SpeechPipelineLog.vad.error("Silero LSTM state arrays unavailable")
            return nil
        }
        do {
            let total = VADService.contextSamples + VADService.chunkSamples // 576
            let audio = try MLMultiArray(shape: [1, 1, NSNumber(value: total)], dataType: .float16)
            let audioPtr = audio.dataPointer.bindMemory(to: Float16.self, capacity: total)
            for index in 0..<VADService.contextSamples {
                audioPtr[index] = Float16(sileroContext[index])
            }
            for index in 0..<VADService.chunkSamples {
                audioPtr[VADService.contextSamples + index] = Float16(chunk[index])
            }

            let provider = try MLDictionaryFeatureProvider(dictionary: [
                "audio": MLFeatureValue(multiArray: audio),
                "h": MLFeatureValue(multiArray: h),
                "c": MLFeatureValue(multiArray: c),
            ])
            let out = try model.prediction(from: provider)

            if let hOut = out.featureValue(for: "h_out")?.multiArrayValue {
                sileroH = hOut
            }
            if let cOut = out.featureValue(for: "c_out")?.multiArrayValue {
                sileroC = cOut
            }
            // Next chunk's context = last 64 samples of this chunk.
            sileroContext = Array(chunk.suffix(VADService.contextSamples))

            guard let prob = out.featureValue(for: "probability")?.multiArrayValue else {
                return nil
            }
            return readFloat(prob, at: 0)
        } catch {
            SpeechPipelineLog.vad.error("Silero infer failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func readFloat(_ array: MLMultiArray, at index: Int) -> Float {
        if array.dataType == .float16 {
            let ptr = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            return Float(ptr[index])
        }
        return Float(truncating: array[index])
    }

    /// Energy + zero-crossing heuristic approximating speech probability for Silero-sized windows.
    private func energyProbability(_ window: [Float]) -> Float {
        guard !window.isEmpty else { return 0 }
        let meanSquare = window.reduce(Float.zero) { $0 + $1 * $1 } / Float(window.count)
        let rms = sqrt(meanSquare)
        let db = 20 * log10(max(rms, 1e-6))
        // Quieter mics: map roughly -60…-12 dBFS → 0…1
        let energyScore = max(0, min(1, (db + 60) / 48))

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
