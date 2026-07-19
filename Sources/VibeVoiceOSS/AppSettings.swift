import Foundation

struct TargetLanguage: Identifiable, Hashable {
    let id: String
    let label: String
    /// Prompt name passed to the translation model. Empty means "no translation".
    let promptName: String
    /// When true, insert both the original transcript and the translation.
    let bilingual: Bool
    /// Extra instruction appended to the translation system prompt.
    let styleHint: String

    var translates: Bool { !promptName.isEmpty }

    /// Whether the expected written output should contain CJK characters.
    var expectsCJK: Bool {
        switch id {
        case "zh-Hans", "yue", "bi-zh-Hans", "bi-yue", "ja", "bi-ja":
            return true
        default:
            return false
        }
    }

    /// Instruction injected into structure / translate prompts.
    var outputLanguageDirective: String {
        guard translates else {
            return "Keep the same language as the source transcript."
        }
        if bilingual {
            return """
            Final user-facing body must be written in \(promptName).
            Do not leave the main narrative in the source language.
            """
        }
        return """
        You MUST write the entire output in \(promptName).
        Do not keep the source language for the main text.
        If the source is English and the target is Chinese, translate fully into Chinese.
        Preserve technical identifiers, product names, and code-like tokens.
        \(styleHint.isEmpty ? "" : "Extra style:\n\(styleHint)")
        """
    }

    /// True when `text` looks compatible with this target (rough script check).
    func outputLooksCompatible(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard expectsCJK else { return true }
        let cjk = trimmed.unicodeScalars.filter { scalar in
            let v = scalar.value
            return (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0x3040...0x30FF).contains(v) // kana
                || (0xAC00...0xD7AF).contains(v) // hangul (rare here)
        }.count
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        // Require a meaningful CJK share once the string is long enough.
        if trimmed.count < 12 {
            return cjk >= 1
        }
        return Double(cjk) >= Double(max(letters, 1)) * 0.25 || cjk >= 8
    }

    var shortLabel: String {
        label.replacingOccurrences(of: "双语 · 原文 + ", with: "")
    }

    static let none = TargetLanguage(
        id: "none",
        label: "原文（不翻译）",
        promptName: "",
        bilingual: false,
        styleHint: ""
    )

    private static let cantoneseHint = """
    Write in 粵語中文 (written Cantonese), NOT Mandarin and NOT standard Traditional Chinese.
    Keep Cantonese vocabulary and grammar such as 嘅、唔、係、嚟、咗、喺、佢哋、睇、睇吓、搞掂.
    Prefer Hong Kong / Guangdong Cantonese written style with traditional characters.
    If the source is spoken Cantonese already, normalize it into natural written Cantonese; do not convert it into Mandarin.
    """

    static let all: [TargetLanguage] = [
        .none,
        TargetLanguage(id: "en", label: "English", promptName: "English", bilingual: false, styleHint: ""),
        TargetLanguage(id: "zh-Hans", label: "简体中文", promptName: "Simplified Chinese", bilingual: false, styleHint: ""),
        TargetLanguage(
            id: "yue",
            label: "粵語中文",
            promptName: "粵語中文 (written Cantonese)",
            bilingual: false,
            styleHint: cantoneseHint
        ),
        TargetLanguage(id: "ja", label: "日本語", promptName: "Japanese", bilingual: false, styleHint: ""),
        TargetLanguage(id: "bi-en", label: "双语 · 原文 + English", promptName: "English", bilingual: true, styleHint: ""),
        TargetLanguage(id: "bi-zh-Hans", label: "双语 · 原文 + 简体中文", promptName: "Simplified Chinese", bilingual: true, styleHint: ""),
        TargetLanguage(
            id: "bi-yue",
            label: "双语 · 原文 + 粵語中文",
            promptName: "粵語中文 (written Cantonese)",
            bilingual: true,
            styleHint: cantoneseHint
        ),
        TargetLanguage(id: "bi-ja", label: "双语 · 原文 + 日本語", promptName: "Japanese", bilingual: true, styleHint: ""),
    ]

    static func resolve(id: String) -> TargetLanguage {
        switch id {
        case "zh-Hant", "prompt":
            // "prompt" used to live in this picker; migrate to 原文 and use the toggle instead.
            return id == "prompt" ? .none : (all.first { $0.id == "yue" } ?? .none)
        case "bi-zh-Hant":
            return all.first { $0.id == "bi-yue" } ?? .none
        default:
            return all.first { $0.id == id } ?? .none
        }
    }

    func formatOutput(transcript: String, translation: String) -> String {
        if bilingual {
            return "\(transcript)\n\(translation)"
        }
        return translation
    }

    var menuCaption: String {
        if !translates { return "仅转写原文" }
        if bilingual { return "识别后输出原文与译文（两行）" }
        return "识别后写成 \(label)"
    }
}

enum LanguageModelTask: String, Sendable {
    case translate
    case optimizePrompt
    case smartRoute
}

enum ASRBackend: String, CaseIterable, Identifiable, Sendable {
    case integrated
    case api

    var id: String { rawValue }

    var label: String {
        switch self {
        case .integrated: "集成模式 · 本地原生"
        case .api: "API 模式 · OpenAI 兼容"
        }
    }

    var caption: String {
        switch self {
        case .integrated:
            "默认使用 WhisperKit 本地转写；Qwen3-ASR 需选择已下载的 MLX 模型目录；不需要 ASR API 服务。"
        case .api:
            "连接 oMLX 或远端 OpenAI-compatible /v1/audio/transcriptions 服务。"
        }
    }
}

enum IntegratedASREngine: String, CaseIterable, Identifiable, Sendable {
    case qwen3MLX
    case whisperMLX

    var id: String { rawValue }

    var label: String {
        switch self {
        case .qwen3MLX: "Qwen3-ASR · mlx-swift-asr"
        case .whisperMLX: "Whisper · WhisperKit"
        }
    }

    var defaultModel: String {
        switch self {
        case .qwen3MLX: "Qwen3-ASR-0.6B-6bit"
        case .whisperMLX: "tiny"
        }
    }

    var caption: String {
        switch self {
        case .qwen3MLX:
            "Swift 原生 MLX 推理，无 Python 运行时；需要选择已下载的 Qwen3-ASR MLX 模型目录。"
        case .whisperMLX:
            "使用 WhisperKit/Core ML，本地自动下载并缓存所选 WhisperKit 模型。"
        }
    }
}

enum LanguageModelBackend: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case api

    var id: String { rawValue }

    var label: String {
        switch self {
        case .disabled: "关闭"
        case .api: "API 模式"
        }
    }

    var caption: String {
        switch self {
        case .disabled:
            "仅输出 ASR 原文；翻译、整理和 Prompt 编译不会运行。"
        case .api:
            "通过 OpenAI-compatible Chat Completions API 执行翻译、整理和 Prompt 编译。"
        }
    }
}

enum TranscodeProfile: String, CaseIterable, Identifiable, Sendable {
    case asr16kMono
    case archive48kStereo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asr16kMono: "ASR 标准 · 16 kHz 单声道 WAV"
        case .archive48kStereo: "存档 · 48 kHz 立体声 WAV"
        }
    }

    var caption: String {
        switch self {
        case .asr16kMono: "送给 oMLX 语音识别的默认规格。"
        case .archive48kStereo: "高质量存档，不直接送 ASR。"
        }
    }

    var sampleRate: Int {
        switch self {
        case .asr16kMono: 16_000
        case .archive48kStereo: 48_000
        }
    }

    var channels: Int {
        switch self {
        case .asr16kMono: 1
        case .archive48kStereo: 2
        }
    }

    var bitDepth: Int { 16 }
    var container: String { "wav" }
    var codec: String { "pcm_s16le" }
}

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let endpoint = "endpoint"
        static let asrBackend = "asrBackend"
        static let integratedASREngine = "integratedASREngine"
        static let integratedASRModelPath = "integratedASRModelPath"
        static let qwenModelRepo = "qwenModelRepo"
        static let whisperKitModel = "whisperKitModel"
        static let model = "model"
        static let language = "language"
        static let prompt = "prompt"
        static let apiKey = "apiKey"
        static let inputDeviceUID = "inputDeviceUID"
        static let launchAtLogin = "launchAtLogin"
        static let targetLanguageID = "targetLanguageID"
        static let translationModel = "translationModel"
        static let promptOptimizeEnabled = "promptOptimizeEnabled"
        static let promptTargetID = "promptTargetID"
        static let structuredOutputEnabled = "structuredOutputEnabled"
        static let structuredEmojiEnabled = "structuredEmojiEnabled"
        static let structureIntensity = "structureIntensity"
        static let streamingMode = "streamingMode"
        static let streamingWSURL = "streamingWSURL"
        static let recordingHotKeyID = "recordingHotKeyID"
        static let llmBackend = "llmBackend"
        static let llmEndpoint = "llmEndpoint"
        static let llmApiKey = "llmApiKey"
        static let llmSystemPrompt = "llmSystemPrompt"
        static let transcodeProfileID = "transcodeProfileID"
        static let transcodeNormalize = "transcodeNormalize"
        static let transcodeMaxGainDb = "transcodeMaxGainDb"
    }

    /// Language rules for Stage 1 IR extraction (string fields inside Prompt IR JSON).
    static let promptOptimizeLanguageRulesBase = """
    Language rules for all Prompt IR string fields:
    - Prefer the language that best matches how the user will paste into the target agent.
    - Keep technical identifiers, paths, symbols, and quoted literals unchanged in preserve_verbatim.
    """

    @Published var asrBackendRaw: String {
        didSet { save(asrBackendRaw, for: Key.asrBackend) }
    }
    @Published var integratedASREngineRaw: String {
        didSet {
            save(integratedASREngineRaw, for: Key.integratedASREngine)
            let engine = IntegratedASREngine(rawValue: integratedASREngineRaw) ?? .whisperMLX
            if engine == .whisperMLX,
               whisperKitModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                whisperKitModel = engine.defaultModel
            }
        }
    }
    @Published var endpoint: String { didSet { save(endpoint, for: Key.endpoint) } }
    @Published var integratedASRModelPath: String {
        didSet { save(integratedASRModelPath, for: Key.integratedASRModelPath) }
    }
    @Published var qwenModelRepo: String {
        didSet { save(qwenModelRepo, for: Key.qwenModelRepo) }
    }
    @Published var whisperKitModel: String {
        didSet { save(whisperKitModel, for: Key.whisperKitModel) }
    }
    @Published var model: String { didSet { save(model, for: Key.model) } }
    @Published var language: String { didSet { save(language, for: Key.language) } }
    @Published var prompt: String { didSet { save(prompt, for: Key.prompt) } }
    @Published var apiKey: String {
        didSet { KeychainStore.set(apiKey, account: .asrAPIKey) }
    }
    @Published var inputDeviceUID: String { didSet { save(inputDeviceUID, for: Key.inputDeviceUID) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    @Published var targetLanguageID: String { didSet { save(targetLanguageID, for: Key.targetLanguageID) } }
    @Published var translationModel: String {
        didSet {
            let cleaned = TranslationClient.sanitizeModelName(translationModel)
            if cleaned != translationModel {
                translationModel = cleaned
                return
            }
            save(translationModel, for: Key.translationModel)
        }
    }
    @Published var promptOptimizeEnabled: Bool {
        didSet { defaults.set(promptOptimizeEnabled, forKey: Key.promptOptimizeEnabled) }
    }
    @Published var promptTargetID: String {
        didSet { save(promptTargetID, for: Key.promptTargetID) }
    }
    @Published var structuredOutputEnabled: Bool {
        didSet { defaults.set(structuredOutputEnabled, forKey: Key.structuredOutputEnabled) }
    }
    /// Decorative emoji in structured layouts. Default off.
    @Published var structuredEmojiEnabled: Bool {
        didSet { defaults.set(structuredEmojiEnabled, forKey: Key.structuredEmojiEnabled) }
    }
    @Published var structureIntensityRaw: String {
        didSet { save(structureIntensityRaw, for: Key.structureIntensity) }
    }
    @Published var streamingModeRaw: String {
        didSet { save(streamingModeRaw, for: Key.streamingMode) }
    }
    @Published var streamingWSURL: String {
        didSet { save(streamingWSURL, for: Key.streamingWSURL) }
    }
    @Published var recordingHotKeyID: String {
        didSet { save(recordingHotKeyID, for: Key.recordingHotKeyID) }
    }
    @Published var llmBackendRaw: String {
        didSet { save(llmBackendRaw, for: Key.llmBackend) }
    }
    @Published var llmEndpoint: String { didSet { save(llmEndpoint, for: Key.llmEndpoint) } }
    @Published var llmApiKey: String {
        didSet { KeychainStore.set(llmApiKey, account: .llmAPIKey) }
    }
    /// User-provided instruction appended to every LLM post-processing system prompt.
    @Published var llmSystemPrompt: String {
        didSet { save(llmSystemPrompt, for: Key.llmSystemPrompt) }
    }
    @Published var transcodeProfileID: String {
        didSet { save(transcodeProfileID, for: Key.transcodeProfileID) }
    }
    @Published var transcodeNormalize: Bool {
        didSet { defaults.set(transcodeNormalize, forKey: Key.transcodeNormalize) }
    }
    @Published var transcodeMaxGainDb: Double {
        didSet { defaults.set(transcodeMaxGainDb, forKey: Key.transcodeMaxGainDb) }
    }

    var structureIntensity: StructureIntensity {
        get { StructureIntensity(rawValue: structureIntensityRaw) ?? .auto }
        set { structureIntensityRaw = newValue.rawValue }
    }

    var asrBackend: ASRBackend {
        get { ASRBackend(rawValue: asrBackendRaw) ?? .integrated }
        set { asrBackendRaw = newValue.rawValue }
    }

    var integratedASREngine: IntegratedASREngine {
        get { IntegratedASREngine(rawValue: integratedASREngineRaw) ?? .whisperMLX }
        set { integratedASREngineRaw = newValue.rawValue }
    }

    var llmBackend: LanguageModelBackend {
        get { LanguageModelBackend(rawValue: llmBackendRaw) ?? .disabled }
        set { llmBackendRaw = newValue.rawValue }
    }

    var llmFeaturesAvailable: Bool {
        llmBackend == .api
            && !llmEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !TranslationClient.sanitizeModelName(translationModel).isEmpty
    }

    var effectiveTargetLanguage: TargetLanguage {
        llmFeaturesAvailable ? targetLanguage : .none
    }

    var streamingMode: StreamingMode {
        get { StreamingMode(rawValue: streamingModeRaw) ?? .duplexStreaming }
        set { streamingModeRaw = newValue.rawValue }
    }

    var recordingHotKey: RecordingHotKey {
        get { RecordingHotKey.resolve(id: recordingHotKeyID) }
        set { recordingHotKeyID = newValue.id }
    }

    var promptTarget: PromptTargetKind {
        get { PromptTargetKind(rawValue: promptTargetID) ?? .codingCodex }
        set { promptTargetID = newValue.rawValue }
    }

    var transcodeProfile: TranscodeProfile {
        get { TranscodeProfile(rawValue: transcodeProfileID) ?? .asr16kMono }
        set { transcodeProfileID = newValue.rawValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedASRBackend = defaults.string(forKey: Key.asrBackend) ?? ASRBackend.integrated.rawValue
        asrBackendRaw = ASRBackend(rawValue: storedASRBackend)?.rawValue ?? ASRBackend.integrated.rawValue
        let storedIntegratedEngine = defaults.string(forKey: Key.integratedASREngine)
            ?? IntegratedASREngine.whisperMLX.rawValue
        integratedASREngineRaw = IntegratedASREngine(rawValue: storedIntegratedEngine)?.rawValue
            ?? IntegratedASREngine.whisperMLX.rawValue
        endpoint = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.endpoint,
            fallback: "http://127.0.0.1:8000/v1/audio/transcriptions"
        )
        integratedASRModelPath = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.integratedASRModelPath,
            fallback: ""
        )
        qwenModelRepo = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.qwenModelRepo,
            fallback: "mlx-community/Qwen3-ASR-0.6B-6bit"
        )
        let storedWhisperKitModel = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.whisperKitModel,
            fallback: IntegratedASREngine.whisperMLX.defaultModel
        )
        let normalizedWhisperKitModel = Self.normalizeWhisperKitModel(storedWhisperKitModel)
        whisperKitModel = normalizedWhisperKitModel
        if normalizedWhisperKitModel != storedWhisperKitModel {
            defaults.set(normalizedWhisperKitModel, forKey: Key.whisperKitModel)
        }
        model = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.model,
            fallback: ""
        )
        language = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.language,
            fallback: "auto"
        )
        let resolvedPrompt = Self.sanitizedASRPrompt(
            KeychainStore.coalesceString(
                defaults: defaults,
                key: Key.prompt,
                fallback: ""
            )
        )
        prompt = resolvedPrompt
        defaults.set(resolvedPrompt, forKey: Key.prompt)
        let resolvedASRKey = KeychainStore.loadOrMigrate(
            account: .asrAPIKey,
            defaults: defaults,
            legacyKey: Key.apiKey
        )
        apiKey = resolvedASRKey
        inputDeviceUID = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.inputDeviceUID,
            fallback: ""
        )
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let storedTarget = defaults.string(forKey: Key.targetLanguageID) ?? TargetLanguage.none.id
        let migratedFromPromptOption = storedTarget == "prompt"
        let resolvedTarget = TargetLanguage.resolve(id: storedTarget)
        targetLanguageID = resolvedTarget.id
        if storedTarget != resolvedTarget.id {
            defaults.set(resolvedTarget.id, forKey: Key.targetLanguageID)
        }
        let resolvedTranslationModel = TranslationClient.sanitizeModelName(
            KeychainStore.coalesceString(
                defaults: defaults,
                key: Key.translationModel,
                fallback: ""
            )
        )
        translationModel = resolvedTranslationModel
        structuredOutputEnabled = defaults.bool(forKey: Key.structuredOutputEnabled)
        // Default OFF when key never set.
        if defaults.object(forKey: Key.structuredEmojiEnabled) == nil {
            structuredEmojiEnabled = false
            defaults.set(false, forKey: Key.structuredEmojiEnabled)
        } else {
            structuredEmojiEnabled = defaults.bool(forKey: Key.structuredEmojiEnabled)
        }
        let storedIntensity = defaults.string(forKey: Key.structureIntensity) ?? StructureIntensity.auto.rawValue
        structureIntensityRaw = StructureIntensity(rawValue: storedIntensity)?.rawValue ?? StructureIntensity.auto.rawValue
        let storedStreaming = defaults.string(forKey: Key.streamingMode) ?? StreamingMode.duplexStreaming.rawValue
        streamingModeRaw = StreamingMode(rawValue: storedStreaming)?.rawValue ?? StreamingMode.duplexStreaming.rawValue
        streamingWSURL = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.streamingWSURL,
            fallback: "ws://127.0.0.1:8000/v1/audio/stream"
        )
        let storedHotKey = defaults.string(forKey: Key.recordingHotKeyID) ?? RecordingHotKey.defaultID
        recordingHotKeyID = RecordingHotKey.resolve(id: storedHotKey).id
        let storedPromptTarget = defaults.string(forKey: Key.promptTargetID) ?? PromptTargetKind.codingCodex.rawValue
        promptTargetID = PromptTargetKind(rawValue: storedPromptTarget)?.rawValue ?? PromptTargetKind.codingCodex.rawValue
        if let storedLLMBackend = defaults.string(forKey: Key.llmBackend) {
            llmBackendRaw = LanguageModelBackend(rawValue: storedLLMBackend)?.rawValue
                ?? LanguageModelBackend.disabled.rawValue
        } else {
            let resolvedLLMBackend = resolvedTranslationModel.isEmpty
                ? LanguageModelBackend.disabled.rawValue
                : LanguageModelBackend.api.rawValue
            llmBackendRaw = resolvedLLMBackend
            defaults.set(resolvedLLMBackend, forKey: Key.llmBackend)
        }
        if defaults.object(forKey: Key.promptOptimizeEnabled) == nil {
            promptOptimizeEnabled = migratedFromPromptOption
            defaults.set(migratedFromPromptOption, forKey: Key.promptOptimizeEnabled)
        } else {
            promptOptimizeEnabled = defaults.bool(forKey: Key.promptOptimizeEnabled) || migratedFromPromptOption
            if migratedFromPromptOption {
                defaults.set(true, forKey: Key.promptOptimizeEnabled)
            }
        }
        // LLM endpoint: prefer saved / legacy, else derive from ASR once when unset.
        let asrEndpointForLLM = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.endpoint,
            fallback: "http://127.0.0.1:8000/v1/audio/transcriptions",
            persistLegacy: false
        )
        if let stored = defaults.string(forKey: Key.llmEndpoint), !stored.isEmpty {
            llmEndpoint = stored
        } else {
            let legacyLLM = KeychainStore.coalesceString(
                defaults: defaults,
                key: Key.llmEndpoint,
                fallback: ""
            )
            if !legacyLLM.isEmpty {
                llmEndpoint = legacyLLM
            } else {
                let derived = Self.deriveChatCompletionsEndpoint(from: asrEndpointForLLM)
                llmEndpoint = derived
                defaults.set(derived, forKey: Key.llmEndpoint)
            }
        }
        // LLM key: Keychain / legacy prefs, else copy ASR key once.
        let resolvedLLMKey = KeychainStore.loadOrMigrate(
            account: .llmAPIKey,
            defaults: defaults,
            legacyKey: Key.llmApiKey
        )
        if resolvedLLMKey.isEmpty, !resolvedASRKey.isEmpty {
            llmApiKey = resolvedASRKey
            KeychainStore.set(resolvedASRKey, account: .llmAPIKey)
        } else {
            llmApiKey = resolvedLLMKey
        }
        llmSystemPrompt = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.llmSystemPrompt,
            fallback: ""
        )
        let storedTranscode = defaults.string(forKey: Key.transcodeProfileID)
            ?? TranscodeProfile.asr16kMono.rawValue
        transcodeProfileID = TranscodeProfile(rawValue: storedTranscode)?.rawValue
            ?? TranscodeProfile.asr16kMono.rawValue
        if defaults.object(forKey: Key.transcodeNormalize) == nil {
            transcodeNormalize = true
            defaults.set(true, forKey: Key.transcodeNormalize)
        } else {
            transcodeNormalize = defaults.bool(forKey: Key.transcodeNormalize)
        }
        if defaults.object(forKey: Key.transcodeMaxGainDb) == nil {
            transcodeMaxGainDb = 18
            defaults.set(18.0, forKey: Key.transcodeMaxGainDb)
        } else {
            transcodeMaxGainDb = defaults.double(forKey: Key.transcodeMaxGainDb)
        }
    }

    private let defaults: UserDefaults

    private func save(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
    }

    nonisolated static func normalizeWhisperKitModel(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "openai_whisper-"
        if trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return trimmed
    }

    var targetLanguage: TargetLanguage {
        TargetLanguage.resolve(id: targetLanguageID)
    }

    var configuration: TranscriptionConfiguration {
        TranscriptionConfiguration(
            backend: asrBackend,
            integratedEngine: integratedASREngine,
            integratedModelPath: integratedASRModelPath,
            qwenModelRepo: qwenModelRepo,
            whisperKitModel: whisperKitModel,
            endpoint: endpoint,
            model: model,
            language: language,
            prompt: prompt,
            apiKey: apiKey
        )
    }

    var translationConfiguration: TranslationConfiguration {
        let language = effectiveTargetLanguage
        return TranslationConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            targetLanguage: language.promptName,
            styleHint: language.styleHint,
            customSystemPrompt: llmSystemPrompt,
            apiKey: llmApiKey,
            task: .translate
        )
    }

    private var promptOptimizeLanguageDirective: String {
        let language = effectiveTargetLanguage
        var lines = [Self.promptOptimizeLanguageRulesBase]
        if !language.translates {
            lines.append("""
            - Write all IR string fields in the same language as the source dictation.
            - Do not switch to English unless the source itself is English (image prompts may still use English visual terms in focus_areas).
            """)
        } else if language.bilingual {
            lines.append("""
            - Write all IR string fields in \(language.promptName).
            - Keep short original terms in preserve_verbatim when needed — do not emit parallel bilingual IR.
            \(language.styleHint.isEmpty ? "" : "Extra style for \(language.promptName):\n\(language.styleHint)")
            """)
        } else {
            lines.append("""
            - Write all IR string fields entirely in \(language.promptName).
            - Do not leave narrative fields in the source language if it differs.
            - Do not mix languages except for unavoidable identifiers in preserve_verbatim.
            \(language.styleHint.isEmpty ? "" : "Extra style requirements:\n\(language.styleHint)")
            """)
        }
        return lines.joined(separator: "\n")
    }

    var promptOptimizeConfiguration: TranslationConfiguration {
        TranslationConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            targetLanguage: effectiveTargetLanguage.promptName,
            styleHint: promptOptimizeLanguageDirective,
            customSystemPrompt: llmSystemPrompt,
            apiKey: llmApiKey,
            task: .optimizePrompt,
            promptTarget: promptTarget
        )
    }

    var smartRouteConfiguration: TranslationConfiguration {
        TranslationConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            targetLanguage: "",
            styleHint: "",
            customSystemPrompt: llmSystemPrompt,
            apiKey: llmApiKey,
            task: .smartRoute
        )
    }

    var hasSmartRoutePrompt: Bool {
        !llmSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func semanticFormatterConfiguration(for transcript: String) -> SemanticFormatterConfiguration {
        let mode = SemanticFormatter.resolveMode(for: transcript, intensity: structureIntensity)
        return SemanticFormatterConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            apiKey: llmApiKey,
            mode: mode,
            customSystemPrompt: llmSystemPrompt,
            outputLanguageDirective: effectiveTargetLanguage.translates
                ? effectiveTargetLanguage.outputLanguageDirective
                : nil,
            useEmoji: structuredEmojiEnabled
        )
    }

    var outputCaption: String {
        var parts: [String] = []
        if !llmFeaturesAvailable {
            parts.append("仅转写原文")
        } else if promptOptimizeEnabled {
            let targetLabel = promptTarget.label
            var suffix: String
            if !targetLanguage.translates {
                suffix = "随口述语言"
            } else if targetLanguage.bilingual {
                suffix = targetLanguage.shortLabel
            } else {
                suffix = targetLanguage.label
            }
            parts.append("Prompt 编译 → \(targetLabel)（\(suffix)）")
        } else if structuredOutputEnabled {
            var structured = "结构化：\(structureIntensity.label)"
            if structuredEmojiEnabled {
                structured += " · Emoji"
            }
            parts.append(structured)
            parts.append(targetLanguage.menuCaption)
        } else {
            parts.append(targetLanguage.menuCaption)
        }
        return parts.joined(separator: " · ")
    }

    /// Caption for a one-shot mode override from a global hotkey.
    func outputCaption(for mode: RecordingOutputMode) -> String {
        guard llmFeaturesAvailable else { return "仅转写原文" }
        switch mode {
        case .conversation:
            return targetLanguage.menuCaption
        case .english:
            return "直接翻译 → English"
        case .structured:
            var structured = "结构化：\(structureIntensity.label)"
            if structuredEmojiEnabled {
                structured += " · Emoji"
            }
            return "\(structured) · \(targetLanguage.menuCaption)"
        case .prompt:
            let targetLabel = promptTarget.label
            if !targetLanguage.translates {
                return "Prompt 编译 → \(targetLabel)（随口述语言）"
            }
            if targetLanguage.bilingual {
                return "Prompt 编译 → \(targetLabel)（\(targetLanguage.shortLabel)）"
            }
            return "Prompt 编译 → \(targetLabel)（\(targetLanguage.label)）"
        case .smartRoute:
            return hasSmartRoutePrompt
                ? "智能路由 → 自定义 System Prompt"
                : "智能路由（未配置 System Prompt）"
        }
    }

    /// Chat Completions endpoint used by translation / structure / prompt optimize.
    var chatCompletionsEndpoint: String { llmEndpoint }

    /// Derive OpenAI chat endpoint from a transcription URL (migration helper).
    static func deriveChatCompletionsEndpoint(from transcriptionEndpoint: String) -> String {
        guard let url = URL(string: transcriptionEndpoint) else {
            return "http://127.0.0.1:8000/v1/chat/completions"
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = url.path
        if path.contains("/audio/transcriptions") {
            components?.path = path.replacingOccurrences(of: "/audio/transcriptions", with: "/chat/completions")
        } else if path.hasSuffix("/v1") {
            components?.path = path + "/chat/completions"
        } else if path.contains("/v1/") {
            components?.path = "/v1/chat/completions"
        } else {
            components?.path = "/v1/chat/completions"
        }
        return components?.string ?? "http://127.0.0.1:8000/v1/chat/completions"
    }

    /// Drop known placeholder prompts that ASR models tend to echo during silence.
    static func sanitizedASRPrompt(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: " ", with: "")
        let junk: Set<String> = [
            "localasr,macos",
            "asr,macos",
            "localasr,macos.",
            "asr,macos.",
            "qwen3-asr,omlx,swift,macos",
            "qwen3-asr，omlx，swift，macos",
        ]
        if junk.contains(normalized) { return "" }
        // Also drop if the whole prompt is only those tokens repeated.
        let stripped = normalized
            .replacingOccurrences(of: "localasr,", with: "")
            .replacingOccurrences(of: "asr,", with: "")
            .replacingOccurrences(of: "macos", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
        if stripped.isEmpty { return "" }
        return trimmed
    }
}
