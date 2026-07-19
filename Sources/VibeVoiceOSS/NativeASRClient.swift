import Foundation
import ArgmaxOSS
import MLXASR
import WhisperKit

struct NativeASRPreparationResult: Sendable {
    let message: String
    let modelPath: String?
}

struct NativeASRDownloadGuidance: Sendable {
    let title: String
    let detail: String
    let manualCommand: String
}

actor NativeASRClient {
    static let shared = NativeASRClient()

    private var qwenModel: Qwen3ASRSTT?
    private var qwenModelPath = ""
    private var whisperKit: WhisperKit?
    private var whisperModel = ""

    func transcribe(wav: Data, configuration: TranscriptionConfiguration) async throws -> String {
        let audioURL = try writeJobWAV(wav)
        defer { try? FileManager.default.removeItem(at: audioURL.deletingLastPathComponent()) }

        switch configuration.integratedEngine {
        case .qwen3MLX:
            return try await transcribeWithQwen(audioURL: audioURL, configuration: configuration)
        case .whisperMLX:
            return try await transcribeWithWhisperKit(audioURL: audioURL, configuration: configuration)
        }
    }

    func checkRuntime(configuration: TranscriptionConfiguration) async throws {
        switch configuration.integratedEngine {
        case .qwen3MLX:
            _ = try await loadQwen(configuration: configuration)
        case .whisperMLX:
            let modelName = effectiveModel(configuration)
            guard !modelName.isEmpty else {
                throw TranscriptionError.localRuntime("请填写 WhisperKit 模型名，例如 tiny 或 large-v3-v20240930_626MB。")
            }
            let folder = localWhisperKitFolder(modelName: modelName)
            guard hasRequiredWhisperKitFiles(in: folder) else {
                throw TranscriptionError.localRuntime("WhisperKit 模型尚未下载完整：\(modelName)。请点击「准备模型」下载或修复缓存。")
            }
            _ = try await loadWhisperKit(configuration: configuration)
        }
    }

    nonisolated static func downloadGuidance(configuration: TranscriptionConfiguration) -> NativeASRDownloadGuidance {
        switch configuration.integratedEngine {
        case .qwen3MLX:
            let repoID = configuration.qwenModelRepo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "mlx-community/Qwen3-ASR-0.6B-6bit"
            let modelName = repoID.components(separatedBy: "/").last ?? "Qwen3-ASR"
            let target = "~/Documents/VibeVoiceOSS/Models/\(modelName)"
            return NativeASRDownloadGuidance(
                title: "Qwen3-ASR 模型准备",
                detail: "会从 Hugging Face 下载 \(repoID)。公开模型通常无需登录；如果遇到 401/403 或 gated repo，请先在终端执行 `hf auth login`。",
                manualCommand: "hf download \(repoID) --local-dir \(target)"
            )
        case .whisperMLX:
            let modelName = AppSettings.normalizeWhisperKitModel(configuration.whisperKitModel).nilIfEmpty
                ?? configuration.integratedEngine.defaultModel
            let variant = whisperKitVariant(modelName)
            return NativeASRDownloadGuidance(
                title: "WhisperKit 模型准备",
                detail: "会从 Hugging Face 下载 argmaxinc/whisperkit-coreml 的 \(variant) 文件。公开模型通常无需登录；如果遇到授权错误，请先执行 `hf auth login`。",
                manualCommand: "hf download argmaxinc/whisperkit-coreml --include \"\(variant)/*\" --local-dir ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml"
            )
        }
    }

    func prepareRuntime(
        configuration: TranscriptionConfiguration,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> NativeASRPreparationResult {
        switch configuration.integratedEngine {
        case .qwen3MLX:
            let directory: URL
            let loadConfiguration: TranscriptionConfiguration
            if let existingDirectory = try? qwenModelDirectory(configuration) {
                directory = existingDirectory
                loadConfiguration = configuration
                onProgress?("已找到本机 Qwen3-ASR 模型：\(directory.lastPathComponent)，正在加载…")
            } else {
                directory = try await downloadQwenModel(configuration: configuration, onProgress: onProgress)
                loadConfiguration = configuration.withIntegratedModelPath(directory.path)
                onProgress?("正在加载 Qwen3-ASR \(directory.lastPathComponent)…")
            }
            _ = try await loadQwen(configuration: loadConfiguration)
            return NativeASRPreparationResult(
                message: "Qwen3-ASR 模型已准备：\(directory.lastPathComponent)",
                modelPath: directory.path
            )
        case .whisperMLX:
            let modelName = effectiveModel(configuration)
            removeCorruptWhisperKitCacheIfNeeded(modelName: modelName)
            let localFolder = localWhisperKitFolder(modelName: modelName)
            let folder: URL
            if hasRequiredWhisperKitFiles(in: localFolder) {
                folder = localFolder
                onProgress?("已找到本机 WhisperKit \(modelName)，正在加载…")
            } else {
                let variant = Self.whisperKitVariant(modelName)
                folder = try await WhisperKit.download(variant: variant) { progress in
                    onProgress?(Self.formatProgress(progress, prefix: "正在下载 WhisperKit \(modelName)"))
                }
                onProgress?("WhisperKit \(modelName) 下载完成，正在加载…")
            }
            let kit = try await WhisperKit(WhisperKitConfig(modelFolder: folder.path, load: true, download: false))
            whisperKit = kit
            whisperModel = modelName
            return NativeASRPreparationResult(
                message: "WhisperKit 模型已准备：\(modelName)",
                modelPath: folder.path
            )
        }
    }

    private func transcribeWithQwen(
        audioURL: URL,
        configuration: TranscriptionConfiguration
    ) async throws -> String {
        let stt = try await loadQwen(configuration: configuration)
        let result = try await stt.transcribe(
            file: audioURL,
            language: qwenLanguage(configuration.language),
            context: configuration.prompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyText }
        return text
    }

    private func transcribeWithWhisperKit(
        audioURL: URL,
        configuration: TranscriptionConfiguration
    ) async throws -> String {
        let kit = try await loadWhisperKit(configuration: configuration)
        var options = whisperDecodingOptions(configuration)

        // Encode recognition hints into prompt tokens for word biasing.
        // Join newline-separated keywords with commas so Whisper treats them
        // as natural context rather than multi-line noise.
        let promptText = configuration.prompt
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let hasPrompt = !promptText.isEmpty
        if hasPrompt, let tokenizer = kit.tokenizer {
            options.promptTokens = tokenizer.encode(text: promptText)
        }

        let results = try await kit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )
        var text = results
            .map(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Retry without prompt tokens if the first pass returned empty.
        if text.isEmpty && hasPrompt {
            var fallback = options
            fallback.promptTokens = nil
            let retryResults = try await kit.transcribe(
                audioPath: audioURL.path,
                decodeOptions: fallback
            )
            text = retryResults
                .map(\.text)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !text.isEmpty else { throw TranscriptionError.emptyText }
        return text
    }

    private func loadQwen(configuration: TranscriptionConfiguration) async throws -> Qwen3ASRSTT {
        let directory = try qwenModelDirectory(configuration)
        let path = directory.path
        if let qwenModel, qwenModelPath == path {
            return qwenModel
        }
        do {
            let model = try await Qwen3ASRSTT.loadWithWarmup(from: directory)
            qwenModel = model
            qwenModelPath = path
            return model
        } catch {
            throw TranscriptionError.localRuntime(
                "Qwen3-ASR 模型加载失败：\(error.localizedDescription)。当前目录：\(path)。请确认目录来自 \(configuration.qwenModelRepo)，或点击「准备模型」重新下载。"
            )
        }
    }

    private func loadWhisperKit(configuration: TranscriptionConfiguration) async throws -> WhisperKit {
        let modelName = effectiveModel(configuration)
        if let whisperKit, whisperModel == modelName {
            return whisperKit
        }
        removeCorruptWhisperKitCacheIfNeeded(modelName: modelName)
        let localFolder = localWhisperKitFolder(modelName: modelName)
        let config: WhisperKitConfig
        if hasRequiredWhisperKitFiles(in: localFolder) {
            config = WhisperKitConfig(modelFolder: localFolder.path, load: true, download: false)
        } else {
            config = WhisperKitConfig(model: Self.whisperKitVariant(modelName), load: true, download: true)
        }
        do {
            let kit = try await WhisperKit(config)
            whisperKit = kit
            whisperModel = modelName
            return kit
        } catch {
            let path = localFolder.path
            throw TranscriptionError.localRuntime(
                "WhisperKit 模型加载失败：\(error.localizedDescription)。当前模型：\(Self.whisperKitVariant(modelName))；目录：\(path)。请点击「准备模型」重新下载，或换成 tiny/base 等受支持模型。"
            )
        }
    }

    private func qwenModelDirectory(_ configuration: TranscriptionConfiguration) throws -> URL {
        let raw = configuration.integratedModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            throw TranscriptionError.localRuntime("请在设置中选择 Qwen3-ASR MLX 模型目录。")
        }
        let expanded = (raw as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw TranscriptionError.localRuntime("Qwen3-ASR 模型目录不存在：\(expanded)")
        }
        let required = ["config.json", "model.safetensors"]
        for file in required {
            let path = URL(fileURLWithPath: expanded).appendingPathComponent(file).path
            guard FileManager.default.fileExists(atPath: path) else {
                throw TranscriptionError.localRuntime("Qwen3-ASR 模型目录缺少 \(file)：\(expanded)")
            }
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private func downloadQwenModel(
        configuration: TranscriptionConfiguration,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> URL {
        let repoID = configuration.qwenModelRepo.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "mlx-community/Qwen3-ASR-0.6B-6bit"
        let hub = HubApiWrapper.shared
        let repo = HubApiWrapper.Repo(id: repoID, type: .models)
        let snapshot = try await hub.snapshot(from: repo) { progress in
            onProgress?(Self.formatProgress(progress, prefix: "正在下载 \(repoID)"))
        }
        let directory = snapshot.appendingPathComponent(repoID.components(separatedBy: "/").last ?? "Qwen3-ASR", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            return directory
        }
        return snapshot
    }

    private func removeCorruptWhisperKitCacheIfNeeded(modelName: String) {
        let folder = localWhisperKitFolder(modelName: modelName)
        guard FileManager.default.fileExists(atPath: folder.path),
              !hasRequiredWhisperKitFiles(in: folder) else {
            return
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private func hasRequiredWhisperKitFiles(in folder: URL) -> Bool {
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            let compiled = folder.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            let package = folder.appendingPathComponent("\(name).mlpackage", isDirectory: true)
            return FileManager.default.fileExists(atPath: compiled.path)
                || FileManager.default.fileExists(atPath: package.path)
        }
    }

    private func localWhisperKitFolder(modelName: String) -> URL {
        defaultHuggingFaceRoot()
            .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
            .appendingPathComponent(Self.whisperKitVariant(modelName), isDirectory: true)
    }

    private func defaultHuggingFaceRoot() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return documents.appendingPathComponent("huggingface", isDirectory: true)
    }

    nonisolated private static func formatProgress(_ progress: Progress, prefix: String) -> String {
        if progress.totalUnitCount > 0 {
            let percent = Int((Double(progress.completedUnitCount) / Double(progress.totalUnitCount)) * 100)
            return "\(prefix)…\(max(0, min(100, percent)))%"
        }
        return "\(prefix)…"
    }

    private func effectiveModel(_ configuration: TranscriptionConfiguration) -> String {
        let trimmed = AppSettings.normalizeWhisperKitModel(configuration.whisperKitModel)
        return trimmed.isEmpty ? configuration.integratedEngine.defaultModel : trimmed
    }

    nonisolated private static func whisperKitVariant(_ modelName: String) -> String {
        let trimmed = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "openai_whisper-"
        if trimmed.hasPrefix(prefix) {
            return trimmed
        }
        return "\(prefix)\(trimmed)"
    }

    private func qwenLanguage(_ raw: String) -> String? {
        switch normalizedLanguage(raw)?.lowercased() {
        case nil, "", "auto":
            return nil
        case "zh", "zh-cn", "zh-hans", "zh-hant", "zh-tw", "cn", "chinese", "中文", "粤语", "廣東話", "cantonese", "yue":
            return "Chinese"
        case "en", "english":
            return "English"
        case let value?:
            return value
        }
    }

    private func whisperDecodingOptions(_ configuration: TranscriptionConfiguration) -> DecodingOptions {
        DecodingOptions(
            task: .transcribe,
            language: whisperLanguage(configuration.language),
            detectLanguage: whisperLanguage(configuration.language) == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
    }

    private func whisperLanguage(_ raw: String) -> String? {
        switch normalizedLanguage(raw)?.lowercased() {
        case nil, "", "auto":
            return nil
        case "zh", "zh-cn", "zh-hans", "zh-hant", "zh-tw", "cn", "chinese", "中文":
            return "zh"
        case "yue", "cantonese", "粤语", "廣東話":
            return "yue"
        case "en", "english":
            return "en"
        case let value?:
            return value
        }
    }

    private func normalizedLanguage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func writeJobWAV(_ wav: Data) throws -> URL {
        let workDir = try runtimeDirectory()
            .appendingPathComponent("jobs", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let audioURL = workDir.appendingPathComponent("recording.wav")
        try wav.write(to: audioURL, options: .atomic)
        return audioURL
    }

    private func runtimeDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("VibeVoiceOSS/NativeASR", isDirectory: true)
    }
}

private extension TranscriptionConfiguration {
    func withIntegratedModelPath(_ path: String) -> TranscriptionConfiguration {
        TranscriptionConfiguration(
            backend: backend,
            integratedEngine: integratedEngine,
            integratedModelPath: path,
            qwenModelRepo: qwenModelRepo,
            whisperKitModel: whisperKitModel,
            endpoint: endpoint,
            model: model,
            language: language,
            prompt: prompt,
            apiKey: apiKey
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
