import Foundation
import VibeVoicePinyin

struct TargetLanguage: Identifiable, Hashable {
    let id: String
    let label: String
    /// Prompt name passed to the translation model.
    let promptName: String
    /// Extra instruction appended to the translation system prompt.
    let styleHint: String

    var translates: Bool { !promptName.isEmpty }

    /// Japanese copy editing is intentionally gated to models with the requested quality floor.
    var minimumModelVersion: Double? { id == "ja" ? 5.6 : nil }

    /// Scripts that provide a useful signal that the model honored this target language.
    private var expectedScriptRanges: [ClosedRange<UInt32>] {
        switch id {
        case "zh-Hans", "zh-Hant-TW", "yue", "ja":
            return [0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3040...0x30FF]
        case "ko":
            return [0xAC00...0xD7AF, 0x1100...0x11FF]
        case "hi":
            return [0x0900...0x097F]
        case "th":
            return [0x0E00...0x0E7F]
        case "el":
            return [0x0370...0x03FF, 0x1F00...0x1FFF]
        case "he":
            return [0x0590...0x05FF]
        case "ar":
            return [0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF]
        default:
            return []
        }
    }

    /// Backward-compatible name used by existing validation tests.
    var expectsCJK: Bool { !expectedScriptRanges.isEmpty }

    /// Instruction injected into structure / translate prompts.
    var outputLanguageDirective: String {
        guard translates else {
            return "Keep the same language as the source transcript."
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
        guard !expectedScriptRanges.isEmpty else { return true }
        let targetScriptCount = trimmed.unicodeScalars.filter { scalar in
            expectedScriptRanges.contains { $0.contains(scalar.value) }
        }.count
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        // Require a meaningful target-script share once the string is long enough.
        if trimmed.count < 12 {
            return targetScriptCount >= 1
        }
        return Double(targetScriptCount) >= Double(max(letters, 1)) * 0.25 || targetScriptCount >= 8
    }

    static let none = TargetLanguage(
        id: "none",
        label: "原文（不翻译）",
        promptName: "",
        styleHint: ""
    )

    private static let cantoneseHint = """
    Write in 粵語中文 (written Cantonese), NOT Mandarin and NOT standard Traditional Chinese.
    Keep Cantonese vocabulary and grammar such as 嘅、唔、係、嚟、咗、喺、佢哋、睇、睇吓、搞掂.
    Prefer Hong Kong / Guangdong Cantonese written style with traditional characters.
    If the source is spoken Cantonese already, normalize it into natural written Cantonese; do not convert it into Mandarin.
    """

    private static let taiwanMandarinHint = """
    Write Taiwan Mandarin in Traditional Chinese, using natural Taiwan wording.
    Add Bopomofo (Zhuyin) phonetic annotations in parentheses immediately after each Chinese phrase.
    Do not use Simplified Chinese or Hanyu Pinyin in the main text.
    """

    private static let japaneseHint = """
    Write natural, idiomatic Japanese as a native Japanese editor would.
    Prefer context-appropriate polite or plain style; do not translate word for word.
    Preserve natural Japanese particles, omitted subjects, sentence endings, and discourse flow.
    Remove spoken fillers, repetition, and abandoned phrasing when the context clearly corrects them.
    Keep names, product names, technical identifiers, paths, and code-like tokens unchanged.
    Output Japanese narrative only. Do not add explanations, labels, or a translation note.
    """

    static let translationOptions: [TargetLanguage] = [
        TargetLanguage(id: "en", label: "English", promptName: "English", styleHint: ""),
        TargetLanguage(id: "zh-Hans", label: "简体中文", promptName: "Simplified Chinese", styleHint: ""),
        TargetLanguage(
            id: "yue",
            label: "粵語中文",
            promptName: "粵語中文 (written Cantonese)",
            styleHint: cantoneseHint
        ),
        TargetLanguage(
            id: "zh-Hant-TW",
            label: "台湾国语（繁体＋注音）",
            promptName: "Taiwan Mandarin in Traditional Chinese with Bopomofo (Zhuyin) annotations",
            styleHint: taiwanMandarinHint
        ),
        TargetLanguage(id: "ja", label: "日本語", promptName: "Japanese", styleHint: japaneseHint),
        TargetLanguage(id: "ko", label: "韩语（한국어）", promptName: "Korean", styleHint: ""),
        TargetLanguage(id: "fr", label: "法语（Français）", promptName: "French", styleHint: ""),
        TargetLanguage(id: "es", label: "西班牙语（Español）", promptName: "Spanish", styleHint: ""),
        TargetLanguage(id: "hi", label: "印地语（Hindi）", promptName: "Hindi", styleHint: ""),
        TargetLanguage(id: "th", label: "泰语（ไทย）", promptName: "Thai", styleHint: ""),
        TargetLanguage(id: "it", label: "义大利语（Italiano）", promptName: "Italian", styleHint: ""),
        TargetLanguage(id: "el", label: "希腊语（Ελληνικά）", promptName: "Greek", styleHint: ""),
        TargetLanguage(id: "he", label: "希伯来语（עברית）", promptName: "Hebrew", styleHint: ""),
        TargetLanguage(id: "ar", label: "阿拉伯语（العربية）", promptName: "Arabic", styleHint: ""),
        TargetLanguage(id: "vi", label: "越南语（Tiếng Việt）", promptName: "Vietnamese", styleHint: ""),
    ]

    /// Original output is always available; translation choices are selected separately.
    static var all: [TargetLanguage] { [.none] + translationOptions }

    static func resolve(id: String) -> TargetLanguage {
        switch id {
        case "zh-Hant": return all.first { $0.id == "zh-Hant-TW" } ?? .none
        case "prompt": return .none // Migrate the retired picker option to original output.
        case "bi-en": return all.first { $0.id == "en" } ?? .none
        case "bi-zh-Hans": return all.first { $0.id == "zh-Hans" } ?? .none
        case "bi-yue": return all.first { $0.id == "yue" } ?? .none
        case "bi-zh-Hant": return all.first { $0.id == "zh-Hant-TW" } ?? .none
        case "bi-ja": return all.first { $0.id == "ja" } ?? .none
        default:
            return all.first { $0.id == id } ?? .none
        }
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
        case .integrated: L10n.t(.asrIntegrated)
        case .api: L10n.t(.asrAPI)
        }
    }

    var caption: String {
        switch self {
        case .integrated: L10n.t(.asrIntegratedCaption)
        case .api: L10n.t(.asrAPICaption)
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
        case .qwen3MLX: L10n.t(.engineQwenCaption)
        case .whisperMLX: L10n.t(.engineWhisperCaption)
        }
    }
}

enum LanguageModelBackend: String, CaseIterable, Identifiable, Sendable {
    case disabled
    case api

    var id: String { rawValue }

    var label: String {
        switch self {
        case .disabled: L10n.t(.llmDisabled)
        case .api: L10n.t(.llmAPI)
        }
    }

    var caption: String {
        switch self {
        case .disabled: L10n.t(.llmDisabledCaption)
        case .api: L10n.t(.llmAPICaption)
        }
    }
}

enum TranscodeProfile: String, CaseIterable, Identifiable, Sendable {
    case asr16kMono
    case archive48kStereo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asr16kMono: L10n.t(.transcodeASR)
        case .archive48kStereo: L10n.t(.transcodeArchive)
        }
    }

    var caption: String {
        switch self {
        case .asr16kMono: L10n.t(.transcodeASRCaption)
        case .archive48kStereo: L10n.t(.transcodeArchiveCaption)
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
        static let hfEndpoint = "hfEndpoint"
        static let model = "model"
        static let language = "language"
        static let prompt = "prompt"
        static let apiKey = "apiKey"
        static let inputDeviceUID = "inputDeviceUID"
        static let launchAtLogin = "launchAtLogin"
        static let targetLanguageID = "targetLanguageID"
        static let targetLanguageIDs = "targetLanguageIDs"
        static let includeOriginalOutput = "includeOriginalOutput"
        static let translationModel = "translationModel"
        static let promptOptimizeEnabled = "promptOptimizeEnabled"
        static let promptTargetID = "promptTargetID"
        static let structuredOutputEnabled = "structuredOutputEnabled"
        static let structuredEmojiEnabled = "structuredEmojiEnabled"
        static let structureIntensity = "structureIntensity"
        static let streamingMode = "streamingMode"
        static let streamingWSURL = "streamingWSURL"
        static let recordingHotKeyID = "recordingHotKeyID"
        static let voicePipelineEnabled = "voicePipelineEnabled"
        static let llmBackend = "llmBackend"
        static let llmEndpoint = "llmEndpoint"
        static let llmApiKey = "llmApiKey"
        static let llmSystemPrompt = "llmSystemPrompt"
        static let candidateRoleIDs = "candidateRoleIDs"
        static let lockedRoleID = "lockedRoleID"
        static let transcodeProfileID = "transcodeProfileID"
        static let transcodeNormalize = "transcodeNormalize"
        static let transcodeMaxGainDb = "transcodeMaxGainDb"
        static let uiLanguageID = "uiLanguageID"
        static let mixedOutputStyle = MixedOutputStyle.defaultsKey
        static let fuzzyPinyinEnabled = PinyinFuzzyCorrector.defaultsKey
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
    @Published var hfEndpoint: String {
        didSet { save(hfEndpoint, for: Key.hfEndpoint) }
    }
    @Published var model: String { didSet { save(model, for: Key.model) } }
    @Published var language: String { didSet { save(language, for: Key.language) } }
    @Published var prompt: String {
        didSet {
            save(prompt, for: Key.prompt)
            syncPromptToSQLite(prompt)
        }
    }
    @Published var apiKey: String {
        didSet { KeychainStore.set(apiKey, account: .asrAPIKey) }
    }
    @Published var inputDeviceUID: String { didSet { save(inputDeviceUID, for: Key.inputDeviceUID) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }
    /// Legacy single-language preference, retained so existing installations migrate cleanly.
    @Published var targetLanguageID: String {
        didSet {
            let resolved = TargetLanguage.resolve(id: targetLanguageID).id
            if targetLanguageID != resolved {
                targetLanguageID = resolved
                return
            }
            save(targetLanguageID, for: Key.targetLanguageID)
            if resolved != TargetLanguage.none.id, targetLanguageIDs != [resolved] {
                targetLanguageIDs = [resolved]
            }
        }
    }
    /// Translation targets emitted after the original transcript. Limited to three.
    @Published var targetLanguageIDs: [String] {
        didSet {
            let normalized = Self.normalizedTargetLanguageIDs(targetLanguageIDs)
            if targetLanguageIDs != normalized {
                targetLanguageIDs = normalized
                return
            }
            defaults.set(targetLanguageIDs, forKey: Key.targetLanguageIDs)
            let first = targetLanguageIDs.first ?? TargetLanguage.none.id
            if targetLanguageID != first {
                targetLanguageID = first
            }
        }
    }
    /// Whether the cleaned source transcript is included alongside translations.
    /// This is independent from the selected translation targets.
    @Published var includeOriginalOutput: Bool {
        didSet { defaults.set(includeOriginalOutput, forKey: Key.includeOriginalOutput) }
    }
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
    /// Experimental always-listen VAD pipeline. Default off; unavailable in API mode.
    @Published var voicePipelineEnabled: Bool {
        didSet { defaults.set(voicePipelineEnabled, forKey: Key.voicePipelineEnabled) }
    }
    @Published var structureIntensityRaw: String {
        didSet { save(structureIntensityRaw, for: Key.structureIntensity) }
    }
    /// How the input method renders mixed pinyin + English compositions.
    @Published var mixedOutputStyleRaw: String {
        didSet {
            save(mixedOutputStyleRaw, for: Key.mixedOutputStyle)
            // IME is a separate process; mirror into the shared suite it reads.
            MixedOutputStyle.save(mixedOutputStyle)
        }
    }
    var mixedOutputStyle: MixedOutputStyle {
        get { MixedOutputStyle(rawValue: mixedOutputStyleRaw) ?? .developer }
        set { mixedOutputStyleRaw = newValue.rawValue }
    }
    /// Cantonese-era fuzzy pinyin (n/l, nasals). Flat/retroflex is never mixed.
    /// Default off — standard Hanyu Pinyin only unless the user opts in.
    @Published var fuzzyPinyinEnabled: Bool {
        didSet {
            defaults.set(fuzzyPinyinEnabled, forKey: Key.fuzzyPinyinEnabled)
            PinyinFuzzyCorrector.setEnabled(fuzzyPinyinEnabled)
        }
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
    @Published private(set) var roleProfiles: [RoleProfile]
    /// Up to three roles can be offered to the resolver for automatic selection.
    @Published var candidateRoleIDs: [String] {
        didSet {
            let normalized = Array(NSOrderedSet(array: candidateRoleIDs).compactMap { $0 as? String }.prefix(3))
            if candidateRoleIDs != normalized {
                candidateRoleIDs = normalized
                return
            }
            defaults.set(candidateRoleIDs, forKey: Key.candidateRoleIDs)
            if let lockedRoleID, !candidateRoleIDs.contains(lockedRoleID) {
                self.lockedRoleID = nil
            }
        }
    }
    /// Nil means automatic selection should run on the next role-aware input.
    @Published var lockedRoleID: String? {
        didSet {
            if let lockedRoleID {
                defaults.set(lockedRoleID, forKey: Key.lockedRoleID)
            } else {
                defaults.removeObject(forKey: Key.lockedRoleID)
            }
        }
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
    /// Interface language (UI only). Independent of ASR / output language.
    @Published var uiLanguageID: String {
        didSet {
            save(uiLanguageID, for: Key.uiLanguageID)
            AppLocalization.shared.apply(uiLanguage)
        }
    }

    var uiLanguage: AppUILanguage {
        get { AppUILanguage.resolve(id: uiLanguageID) }
        set { uiLanguageID = newValue.rawValue }
    }

    var structureIntensity: StructureIntensity {
        get { StructureIntensity(rawValue: structureIntensityRaw) ?? .auto }
        set { structureIntensityRaw = newValue.rawValue }
    }

    var asrBackend: ASRBackend {
        get { ASRBackend(rawValue: asrBackendRaw) ?? .integrated }
        set {
            asrBackendRaw = newValue.rawValue
            // Voice Pipeline is local-only; force off when switching to API mode.
            if newValue == .api, voicePipelineEnabled {
                voicePipelineEnabled = false
            }
        }
    }

    /// Voice Pipeline is only meaningful with integrated local ASR.
    var isVoicePipelineAvailable: Bool { asrBackend == .integrated }

    /// Effective flag used by runtime paths (always false in API mode).
    var effectiveVoicePipelineEnabled: Bool {
        isVoicePipelineAvailable && voicePipelineEnabled
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

    /// True when a mirror was typed but rejected, so model downloads silently fall
    /// back to the default Hugging Face host.
    var hfEndpointRejected: Bool {
        !hfEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && configuration.normalizedHFEndpoint == nil
    }

    var effectiveTargetLanguage: TargetLanguage {
        effectiveTargetLanguages.first ?? .none
    }

    var effectiveTargetLanguages: [TargetLanguage] {
        llmFeaturesAvailable ? targetLanguages : []
    }

    var outputModeCapabilities: OutputModePlan.Capabilities {
        OutputModePlan.Capabilities(
            llmAvailable: llmFeaturesAvailable,
            structuredOutputEnabled: structuredOutputEnabled,
            hasCustomFormattingPrompt: hasCustomFormattingPrompt,
            promptOptimizeEnabled: promptOptimizeEnabled,
            promptTargetLabel: promptTarget.label,
            roleModeEnabled: roleModeEnabled
        )
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
        hfEndpoint = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.hfEndpoint,
            fallback: ""
        )
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
        var rawPrompt = KeychainStore.coalesceString(
            defaults: defaults,
            key: Key.prompt,
            fallback: ""
        )
        // Recover from SQLite if UserDefaults is empty (e.g. after a fresh install).
        if rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sqliteWords = DataStore.shared.loadRecognitionPrompts()
            if !sqliteWords.isEmpty {
                rawPrompt = sqliteWords.joined(separator: "\n")
            }
        }
        let resolvedPrompt = Self.sanitizedASRPrompt(rawPrompt)
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
        let storedTargets = defaults.stringArray(forKey: Key.targetLanguageIDs)
        let resolvedTargetIDs = Self.normalizedTargetLanguageIDs(
            storedTargets ?? (resolvedTarget.translates ? [resolvedTarget.id] : [])
        )
        targetLanguageIDs = resolvedTargetIDs
        if let storedIncludeOriginal = defaults.object(forKey: Key.includeOriginalOutput) as? Bool {
            includeOriginalOutput = storedIncludeOriginal
        } else {
            // Existing installations that already selected a translation should not
            // silently keep the old forced "original + translation" behavior.
            let defaultIncludeOriginal = resolvedTargetIDs.isEmpty
            includeOriginalOutput = defaultIncludeOriginal
            defaults.set(defaultIncludeOriginal, forKey: Key.includeOriginalOutput)
        }
        if storedTarget != resolvedTarget.id {
            defaults.set(resolvedTarget.id, forKey: Key.targetLanguageID)
        }
        if storedTargets == nil {
            defaults.set(resolvedTargetIDs, forKey: Key.targetLanguageIDs)
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
        // Default off. API mode cannot enable Voice Pipeline.
        let storedVoicePipeline = defaults.bool(forKey: Key.voicePipelineEnabled)
        let pipelineAllowed = storedASRBackend != ASRBackend.api.rawValue
        voicePipelineEnabled = storedVoicePipeline && pipelineAllowed
        if storedVoicePipeline, !pipelineAllowed {
            defaults.set(false, forKey: Key.voicePipelineEnabled)
        }
        let storedIntensity = defaults.string(forKey: Key.structureIntensity) ?? StructureIntensity.auto.rawValue
        structureIntensityRaw = StructureIntensity(rawValue: storedIntensity)?.rawValue ?? StructureIntensity.auto.rawValue
        let storedMixed = defaults.string(forKey: Key.mixedOutputStyle)
            ?? MixedOutputStyle.load().rawValue
        let resolvedMixed = MixedOutputStyle(rawValue: storedMixed) ?? .developer
        mixedOutputStyleRaw = resolvedMixed.rawValue
        MixedOutputStyle.save(resolvedMixed)
        let fuzzyEnabled = PinyinFuzzyCorrector.isEnabled(defaults: defaults)
        fuzzyPinyinEnabled = fuzzyEnabled
        PinyinFuzzyCorrector.setEnabled(fuzzyEnabled)
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
        DataStore.shared.ensureDefaultRoleProfiles()
        let loadedRoles = DataStore.shared.loadRoleProfiles()
        let loadedCandidateRoleIDs = Array((defaults.stringArray(forKey: Key.candidateRoleIDs) ?? [])
            .filter { id in loadedRoles.contains(where: { $0.id == id }) }
            .prefix(3))
        roleProfiles = loadedRoles
        candidateRoleIDs = loadedCandidateRoleIDs
        let storedLockedRoleID = defaults.string(forKey: Key.lockedRoleID)
        lockedRoleID = storedLockedRoleID.flatMap { id in
            loadedCandidateRoleIDs.contains(id) && loadedRoles.contains(where: { $0.id == id }) ? id : nil
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
        let storedUILanguage = defaults.string(forKey: Key.uiLanguageID)
        uiLanguageID = AppUILanguage.resolve(id: storedUILanguage).rawValue
        AppLocalization.shared.apply(uiLanguage)
        // All stored properties are now initialized — safe to call instance methods.
        syncPromptToSQLite(resolvedPrompt)
    }

    private let defaults: UserDefaults

    private func save(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
    }

    private func syncPromptToSQLite(_ prompt: String) {
        let words = prompt
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "，") }
            .flatMap { $0.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        DataStore.shared.saveRecognitionPrompts(words)
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
        targetLanguages.first ?? .none
    }

    var targetLanguages: [TargetLanguage] {
        targetLanguageIDs.compactMap { id in
            let language = TargetLanguage.resolve(id: id)
            return language.translates ? language : nil
        }
    }

    var outputLanguageSummary: String {
        guard !targetLanguages.isEmpty else { return "仅原文" }
        let labels = (includeOriginalOutput ? ["原文"] : []) + targetLanguages.map(\.label)
        return labels.joined(separator: " + ")
    }

    var canSelectMoreTargetLanguages: Bool { targetLanguageIDs.count < 3 }

    func isTargetLanguageSelected(_ language: TargetLanguage) -> Bool {
        targetLanguageIDs.contains(language.id)
    }

    func setTargetLanguageSelected(_ language: TargetLanguage, selected: Bool) {
        guard language.translates else { return }
        if selected {
            guard !targetLanguageIDs.contains(language.id), targetLanguageIDs.count < 3 else { return }
            targetLanguageIDs.append(language.id)
            // Choosing a translation is a distinct output mode. The original can
            // still be added explicitly with the checkbox in the same menu.
            if targetLanguageIDs.count == 1 && includeOriginalOutput {
                includeOriginalOutput = false
            }
        } else {
            targetLanguageIDs.removeAll { $0 == language.id }
        }
    }

    func setIncludeOriginalOutput(_ included: Bool) {
        // Never allow an empty output selection: with no translation selected,
        // the only meaningful result is the original transcript.
        guard included || !targetLanguages.isEmpty else {
            includeOriginalOutput = true
            return
        }
        includeOriginalOutput = included
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
            apiKey: apiKey,
            hfEndpoint: hfEndpoint
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
            roleContextPrompt: effectiveRole?.contextPrompt ?? "",
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
            roleContextPrompt: effectiveRole?.contextPrompt ?? "",
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
            roleContextPrompt: effectiveRole?.contextPrompt ?? "",
            apiKey: llmApiKey,
            task: .smartRoute
        )
    }

    var hasSmartRoutePrompt: Bool {
        !llmSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var activeRoleCandidates: [RoleProfile] {
        candidateRoleIDs.compactMap { id in roleProfiles.first(where: { $0.id == id }) }
    }

    var lockedRole: RoleProfile? {
        guard let lockedRoleID else { return nil }
        return roleProfiles.first(where: { $0.id == lockedRoleID })
    }

    var effectiveRole: RoleProfile? { lockedRole }

    var roleModeEnabled: Bool { !activeRoleCandidates.isEmpty }

    var roleSummary: String {
        if let role = lockedRole { return "已锁定：\(role.name)" }
        if activeRoleCandidates.isEmpty { return "未启用" }
        return "自动判定（\(activeRoleCandidates.map(\.name).joined(separator: "、"))）"
    }

    func isRoleSelected(_ role: RoleProfile) -> Bool {
        candidateRoleIDs.contains(role.id)
    }

    func canSelectMoreRoles(excluding role: RoleProfile? = nil) -> Bool {
        candidateRoleIDs.count < 3 || (role.map(isRoleSelected) ?? false)
    }

    func setRoleSelected(_ role: RoleProfile, selected: Bool) {
        if selected {
            guard !candidateRoleIDs.contains(role.id), candidateRoleIDs.count < 3 else { return }
            candidateRoleIDs.append(role.id)
        } else {
            candidateRoleIDs.removeAll { $0 == role.id }
        }
    }

    func lockRole(_ role: RoleProfile?) {
        if let role, !candidateRoleIDs.contains(role.id) {
            setRoleSelected(role, selected: true)
        }
        lockedRoleID = role?.id
    }

    func saveRole(_ profile: RoleProfile) {
        var value = profile
        value.updatedAt = .now
        DataStore.shared.saveRoleProfile(value)
        roleProfiles = DataStore.shared.loadRoleProfiles()
    }

    func deleteRole(_ profile: RoleProfile) {
        DataStore.shared.deleteRoleProfile(id: profile.id)
        candidateRoleIDs.removeAll { $0 == profile.id }
        if lockedRoleID == profile.id { lockedRoleID = nil }
        roleProfiles = DataStore.shared.loadRoleProfiles()
    }

    func restoreDefaultRoles() {
        DataStore.shared.ensureDefaultRoleProfiles()
        roleProfiles = DataStore.shared.loadRoleProfiles()
    }

    /// A custom post-process instruction is actionable even when the structured-output switch is off.
    var hasCustomFormattingPrompt: Bool { hasSmartRoutePrompt }

    func semanticFormatterConfiguration(for transcript: String) -> SemanticFormatterConfiguration {
        let mode = SemanticFormatter.resolveMode(for: transcript, intensity: structureIntensity)
        return SemanticFormatterConfiguration(
            endpoint: llmEndpoint,
            model: TranslationClient.sanitizeModelName(translationModel),
            apiKey: llmApiKey,
            mode: mode,
            customSystemPrompt: llmSystemPrompt,
            roleContextPrompt: effectiveRole?.contextPrompt ?? "",
            outputLanguageDirective: nil,
            useEmoji: structuredEmojiEnabled
        )
    }

    var outputCaption: String {
        var parts: [String] = []
        if !llmFeaturesAvailable {
            parts.append(L10n.t(.captionASROnly))
        } else if promptOptimizeEnabled {
            let targetLabel = promptTarget.label
            let suffix = targetLanguage.translates ? targetLanguage.label : L10n.t(.followSpokenLanguage)
            parts.append(L10n.t(.promptCompileArrow, targetLabel, suffix))
        } else if structuredOutputEnabled {
            var structured = L10n.t(.structuredPrefix, structureIntensity.label)
            if structuredEmojiEnabled {
                structured += " · Emoji"
            }
            parts.append(structured)
            parts.append(outputLanguageSummary)
        } else {
            parts.append(outputLanguageSummary)
        }
        return parts.joined(separator: " · ")
    }

    /// Caption for a one-shot mode override from a global hotkey.
    func outputCaption(for mode: RecordingOutputMode) -> String {
        guard llmFeaturesAvailable else { return L10n.t(.captionASROnly) }
        switch mode {
        case .conversation:
            return outputLanguageSummary
        case .english:
            return L10n.t(.captionDirectEnglish)
        case .structured:
            var structured = L10n.t(.structuredPrefix, structureIntensity.label)
            if structuredEmojiEnabled {
                structured += " · Emoji"
            }
            return "\(structured) · \(outputLanguageSummary)"
        case .prompt:
            let targetLabel = promptTarget.label
            if !targetLanguage.translates {
                return L10n.t(.promptCompileArrow, targetLabel, L10n.t(.followSpokenLanguage))
            }
            return L10n.t(.promptCompileArrow, targetLabel, targetLanguage.label)
        case .smartRoute:
            return L10n.t(.captionSmartRoute)
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

    private static func normalizedTargetLanguageIDs(_ ids: [String]) -> [String] {
        var result: [String] = []
        for id in ids {
            let language = TargetLanguage.resolve(id: id)
            guard language.translates, !result.contains(language.id) else { continue }
            result.append(language.id)
            if result.count == 3 { break }
        }
        return result
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
