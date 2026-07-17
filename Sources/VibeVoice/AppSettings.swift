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
        static let llmEndpoint = "llmEndpoint"
        static let llmApiKey = "llmApiKey"
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

    @Published var endpoint: String { didSet { save(endpoint, for: Key.endpoint) } }
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
    @Published var llmEndpoint: String { didSet { save(llmEndpoint, for: Key.llmEndpoint) } }
    @Published var llmApiKey: String {
        didSet { KeychainStore.set(llmApiKey, account: .llmAPIKey) }
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
        endpoint = defaults.string(forKey: Key.endpoint)
            ?? "http://127.0.0.1:8000/v1/audio/transcriptions"
        model = defaults.string(forKey: Key.model)
            ?? "mlx-community/Qwen3-ASR-0.6B-4bit"
        language = defaults.string(forKey: Key.language) ?? "zh"
        prompt = defaults.string(forKey: Key.prompt) ?? "local ASR, macOS"
        let resolvedASRKey = KeychainStore.loadOrMigrate(
            account: .asrAPIKey,
            defaults: defaults,
            legacyKey: Key.apiKey
        )
        apiKey = resolvedASRKey
        inputDeviceUID = defaults.string(forKey: Key.inputDeviceUID) ?? ""
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        let storedTarget = defaults.string(forKey: Key.targetLanguageID) ?? TargetLanguage.none.id
        let migratedFromPromptOption = storedTarget == "prompt"
        let resolvedTarget = TargetLanguage.resolve(id: storedTarget)
        targetLanguageID = resolvedTarget.id
        if storedTarget != resolvedTarget.id {
            defaults.set(resolvedTarget.id, forKey: Key.targetLanguageID)
        }
        translationModel = TranslationClient.sanitizeModelName(
            defaults.string(forKey: Key.translationModel) ?? ""
        )
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
        streamingWSURL = defaults.string(forKey: Key.streamingWSURL)
            ?? "ws://127.0.0.1:8000/v1/audio/stream"
        let storedHotKey = defaults.string(forKey: Key.recordingHotKeyID) ?? RecordingHotKey.defaultID
        recordingHotKeyID = RecordingHotKey.resolve(id: storedHotKey).id
        let storedPromptTarget = defaults.string(forKey: Key.promptTargetID) ?? PromptTargetKind.codingCodex.rawValue
        promptTargetID = PromptTargetKind(rawValue: storedPromptTarget)?.rawValue ?? PromptTargetKind.codingCodex.rawValue
        if defaults.object(forKey: Key.promptOptimizeEnabled) == nil {
            promptOptimizeEnabled = migratedFromPromptOption
            defaults.set(migratedFromPromptOption, forKey: Key.promptOptimizeEnabled)
        } else {
            promptOptimizeEnabled = defaults.bool(forKey: Key.promptOptimizeEnabled) || migratedFromPromptOption
            if migratedFromPromptOption {
                defaults.set(true, forKey: Key.promptOptimizeEnabled)
            }
        }
        // LLM endpoint: derive from ASR once when unset.
        let asrEndpoint = defaults.string(forKey: Key.endpoint)
            ?? "http://127.0.0.1:8000/v1/audio/transcriptions"
        if let stored = defaults.string(forKey: Key.llmEndpoint), !stored.isEmpty {
            llmEndpoint = stored
        } else {
            let derived = Self.deriveChatCompletionsEndpoint(from: asrEndpoint)
            llmEndpoint = derived
            defaults.set(derived, forKey: Key.llmEndpoint)
        }
        // LLM key: Keychain first; migrate legacy UserDefaults; else copy ASR key once.
        if let fromKeychain = KeychainStore.get(.llmAPIKey) {
            llmApiKey = fromKeychain
            defaults.removeObject(forKey: Key.llmApiKey)
        } else if let legacy = defaults.string(forKey: Key.llmApiKey) {
            llmApiKey = legacy
            KeychainStore.set(legacy, account: .llmAPIKey)
            defaults.removeObject(forKey: Key.llmApiKey)
        } else {
            llmApiKey = resolvedASRKey
            KeychainStore.set(resolvedASRKey, account: .llmAPIKey)
        }
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

    var targetLanguage: TargetLanguage {
        TargetLanguage.resolve(id: targetLanguageID)
    }

    var configuration: TranscriptionConfiguration {
        TranscriptionConfiguration(
            endpoint: endpoint,
            model: model,
            language: language,
            prompt: prompt,
            apiKey: apiKey
        )
    }

    var translationConfiguration: TranslationConfiguration {
        let language = targetLanguage
        return TranslationConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            targetLanguage: language.promptName,
            styleHint: language.styleHint,
            apiKey: llmApiKey,
            task: .translate
        )
    }

    private var promptOptimizeLanguageDirective: String {
        let language = targetLanguage
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
            targetLanguage: targetLanguage.promptName,
            styleHint: promptOptimizeLanguageDirective,
            apiKey: llmApiKey,
            task: .optimizePrompt,
            promptTarget: promptTarget
        )
    }

    func semanticFormatterConfiguration(for transcript: String) -> SemanticFormatterConfiguration {
        let mode = SemanticFormatter.resolveMode(for: transcript, intensity: structureIntensity)
        return SemanticFormatterConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            apiKey: llmApiKey,
            mode: mode,
            outputLanguageDirective: targetLanguage.translates
                ? targetLanguage.outputLanguageDirective
                : nil,
            useEmoji: structuredEmojiEnabled
        )
    }

    var outputCaption: String {
        var parts: [String] = []
        if promptOptimizeEnabled {
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
        switch mode {
        case .conversation:
            return targetLanguage.menuCaption
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
}
