import Foundation

/// UI string catalog. LLM / ASR prompts stay in their original language.
enum L10n {
    enum Key: String, CaseIterable {
        // MARK: Common
        case copied
        case copyTranscript
        case copyCurrentText
        case settingsEllipsis
        case cancel
        case done
        case failed
        case success
        case close
        case enabled
        case disabled
        case detailsInSettings
        case followSpokenLanguage

        // MARK: Menu
        case startRecording
        case stopAndTranscribe
        case cancelTranscribe
        case cancelFinalize
        case cancelStructure
        case cancelTranslate
        case cancelOptimize
        case cancelRoute
        case outputLanguage
        case promptOptimize
        case targetAgent
        case moreOutputOptions
        case useStructuredOutput
        case useEmoji
        case structureIntensity
        case llmNotConfiguredASROnly
        case testConnection
        case testConnectionHelp
        case stageTiming
        case stageTimingHelp
        case tokenUsage
        case tokenUsageHelp
        case quitApp
        case windowStageTiming
        case windowTokenUsage

        // MARK: Phase / HUD
        case phaseIdle
        case phaseIdleHotKey // %@
        case phaseRecording
        case phaseRecordingHotKey // %@
        case phaseRecordingMode // %@ mode, %@ chord
        case phaseFinalizing
        case phaseTranscribing
        case phaseStructuring
        case phaseTranslating
        case phaseOptimizing
        case phaseRouting
        case hudRecording
        case hudFinalizing
        case hudTranscribing
        case hudStructuring
        case hudTranslating
        case hudOptimizing
        case hudRouting
        case hudCustomSystemPrompt
        case hudWaitingSpeak
        case hudWaitingFinalizing
        case hudWaitingTranscribing
        case hudWaitingStructuring
        case hudWaitingTranslating
        case hudWaitingOptimizing
        case hudWaitingRouting
        case hudWaitingFailed
        case hudWaitingSuccess
        case hudListening // %@ dots appended in code via format or base
        case stopAndCancel
        case stopAccessibilityHint
        case copyAccessibilityHint

        // MARK: Recording modes
        case modeConversation
        case modeEnglish
        case modeStructured
        case modePrompt
        case modeSmartRoute
        case modeConversationCaption
        case modeEnglishCaption
        case modeStructuredCaption
        case modePromptCaption
        case modeSmartRouteCaption
        case pressHotKey // %@
        case toggleHotKeyHint // %@

        // MARK: Streaming
        case streamingBatch
        case streamingSSE
        case streamingDuplex
        case streamingBatchCaption
        case streamingSSECaption
        case streamingDuplexCaption

        // MARK: Backends
        case asrIntegrated
        case asrAPI
        case asrIntegratedCaption
        case asrAPICaption
        case engineQwenCaption
        case engineWhisperCaption
        case llmDisabled
        case llmAPI
        case llmDisabledCaption
        case llmAPICaption
        case transcodeASR
        case transcodeArchive
        case transcodeASRCaption
        case transcodeArchiveCaption

        // MARK: Structure intensity
        case intensityAuto
        case intensityClean
        case intensityUltraConcise
        case intensityStructured
        case intensityRewrite
        case intensityAutoCaption
        case intensityCleanCaption
        case intensityUltraConciseCaption
        case intensityStructuredCaption
        case intensityRewriteCaption

        // MARK: Prompt targets (UI labels only)
        case promptTargetChat
        case promptTargetResearch
        case promptTargetImage
        case promptTargetChatCaption
        case promptTargetCodexCaption
        case promptTargetClaudeCaption
        case promptTargetGrokCaption
        case promptTargetResearchCaption
        case promptTargetImageCaption

        // MARK: Output captions
        case captionASROnly
        case captionDirectEnglish
        case captionSmartRoute

        // MARK: Settings panes
        case paneGeneral
        case paneRecognition
        case paneAudio
        case paneTranslation
        case panePrompt
        case paneShortcuts
        case panePerformance
        case uiLanguage
        case uiLanguageCaption
        case mixedOutputStyle
        case mixedOutputStyleCaption
        case mixedOutputDeveloper
        case mixedOutputSmartChinese
        case mixedOutputOriginal
        case fuzzyPinyin
        case fuzzyPinyinCaption
        case importProjectVocabulary
        case importProjectVocabularyCaption
        case importProjectVocabularyDone
        case sharedCorrectionLexiconStatus
        case settingsASRMode
        case settingsEngine
        case settingsModel
        case settingsEndpoint
        case settingsAPIKey
        case settingsInputDevice
        case settingsLaunchAtLogin
        case settingsStreamingMode
        case settingsDuplexWS
        case settingsLLMBackend
        case settingsLLMEndpoint
        case settingsLLMModel
        case settingsSystemPrompt
        case settingsTranscodeProfile
        case settingsNormalize
        case settingsCheckASR
        case settingsTestASR
        case settingsTestTranslation
        case settingsCheckPermissions
        case settingsOpenTiming
        case settingsQwenRepo
        case settingsModelPath
        case settingsWhisperKitModel
        case settingsPrepareModel

        // MARK: Settings fields / captions (high-traffic)
        case latestTotal // used with values in view
        case stageTimingEmptyCaption
        case recognitionLanguage
        case recognitionLanguageCaption
        case modelNameMatchCaption
        case liveCaptionCaption
        case streamingModeAPIOnlyCaption
        case integratedNoStreamingCaption
        case localAudioSpecCaption
        case llmSystemPromptCaption
        case llmModelKeyCaption
        case llmFeaturesOffCaption
        case emojiOnCaption
        case emojiOffCaption
        case llmOnlyWhenConfiguredCaption
        case promptHintWordsCaption
        case shortcutsToggleCaption
        case bluetoothAudioCaption
        case prepareModel
        case checkLocalASR
        case openStageTimingReport
        case openTokenUsageReport
        case voicePipeline
        case voicePipelineCaption
        case voicePipelineUnavailable
        case qwenRepoCaption
        case currentModel
        case modelFilesCaption
        case hfEndpointCaption
        case apiKeyOptional
        case recognitionMode
        case streamingFallbackCaption
        case cancelDownload
        case sampleRate
        case channels
        case codec
        case maxGain
        case customPrompt
        case customPromptCaption
        case outputLanguageCombination
        case outputLanguageCombinationCaption
        case providerProfileCaption
        case apiKeyStorageCaption
        case structuredEmojiCaptionOn
        case structuredEmojiCaptionOff
        case shortcutsCaption
        case recordingInput
        case currentPlaybackOutput
        case bluetoothRefresh
        case choose

        // MARK: Reports
        case timingNoRecords
        case timingNoRecordsCaption
        case timingHeader
        case timingLatest
        case timingDescription
        case timingActive
        case exportCSV
        case exportHTML
        case clearRecords
        case exportTimingCSV
        case exportTimingHTML
        case exportCancelled
        case exportSuccess
        case exportFailed
        case tokenUsageHeader
        case tokenUsageCaption
        case tokenNoData
        case tokenNoDataCaption
        case tokenCumulative
        case tokenRecent
        case tokenRecordCount
        case tokenInput
        case tokenCachedInput
        case tokenOutput
        case tokenReasoning
        case tokenAudioInput
        case tokenAudioOutput
        case tokenAudioDuration
        case tokenTotal
        case stageRecording
        case stageFinalizing
        case stageTranscribing
        case stageStructuring
        case stageTranslating
        case stageOptimizing
        case stagePaste
        case outcomeSuccess
        case outcomeFailed
        case outcomeCancelled
        case timingHTMLNoStage
        case timingHTMLGenerated
        case timingHTMLTotal
        case timingHTMLResult
        case timingHTMLTarget
        case timingHTMLFirstPartial
        case timingHTMLStage
        case timingHTMLMilliseconds
        case timingHTMLDuration
        case timingHTMLNoRecords
        case japaneseModelRequirement
        case japaneseNaturalCaption

        // MARK: Result banner
        case justNow
        case recognitionComplete
        case copyButtonTitle
        case reformatButtonTitle

        // MARK: Status / errors (user-facing)
        case supersededByNewRecording
        case pasteFailedNoFocus
        case pasteFailedDetail // %@
        case cancelled
        case cancelledPeriod
        case checkingLocalASR
        case localASRFirstUseHint
        case localASRReady
        case localASRCheckFailed // %@
        case connectingASRAPI
        case probingStreaming
        case asrConnectOK
        case asrConnectFailed // %@
        case apiNoLocalModel
        case preparingLocalASR
        case prepareLocalASRFailed // %@
        case llmPostProcessOff
        case configureLLMFirst
        case connectingTranslation
        case translationConnectFailed // %@
        case testingConnections
        case checkingNativeASR
        case localASROK
        case asrAPIOK
        case asrFailed // %@
        case llmNotEnabled
        case translationFailed // %@
        case enableLLMInSettings
        case reformatPasteFailed
        case reformatPasteFailedDetail // %@
        case launchAtLoginNeedAllow
        case launchAtLoginOn
        case launchAtLoginOff
        case launchAtLoginFailed // %@
        case accessibilityGranted
        case accessibilityPromptOpened
        case structuredPrefix // used in outputCaption
        case promptCompileArrow // Prompt 编译 →

        // MARK: Security warnings
        case cleartextEndpointWarning
        case hfEndpointRejected
        case vadBackendSilero
        case vadBackendEnergy
        case vadEnergyFallbackDetail
        case cleartextEndpointDetail
        case credentialsPlaintextWarning
        case shortcutTaken
        case shortcutsUnavailableDetail

        // MARK: Thrown errors (LocalizedError.errorDescription)
        case errInsecureEndpoint
        case errMicrophoneDenied
        case errDeviceUnavailable // %@ device
        case errDeviceCannotSelect // %@ device, %d OSStatus
        case errNoSamples
        case errNoAudibleSignal // %@ device
        case errInvalidInputFormat // %@ device
        case errTapInstallFailed // %@ device
        case errASRInvalidEndpoint
        case errASRServer // %d status, %@ body
        case errASRInvalidResponse
        case errASREmptyText
        case errASRTimedOut
        case errASRLocalTimedOut // %d minutes
        case errASRLocalRuntime // %@
        case errLLMInvalidEndpoint
        case errLLMServer // %d status, %@ body
        case errLLMInvalidResponse
        case errLLMEmptyText
        case errLLMTimedOut // %d seconds
        case errFormatInvalidEndpoint
        case errFormatServer // %d status, %@ body
        case errFormatInvalidResponse
        case errFormatEmptyText
        case errFormatTimedOut // %d seconds
        case errPromptCompile // %@
        case errPromptIRInvalid // %@
        case errPromptIREmpty
        case errAccessibilityDenied
        case errCannotCreateEvent
        case errVADModelMissing // %@ path
        case errVADModelLoadFailed // %@
        case errPipelineNeedsLocalASR
        case errPipelineEmptyText
    }

    private final class LanguageBox: @unchecked Sendable {
        let lock = NSLock()
        var language: AppUILanguage = .zhHans
    }

    private static let box = LanguageBox()

    static var language: AppUILanguage {
        get {
            box.lock.lock(); defer { box.lock.unlock() }
            return box.language
        }
        set {
            box.lock.lock(); box.language = newValue; box.lock.unlock()
        }
    }

    static func t(_ key: Key) -> String {
        string(key, language: language)
    }

    static func t(_ key: Key, _ arguments: CVarArg...) -> String {
        let format = string(key, language: language)
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    static func string(_ key: Key, language: AppUILanguage) -> String {
        let table: [Key: String]
        switch language {
        case .zhHans: table = chinese
        case .english: table = english
        case .japanese: table = japanese
        }
        return table[key] ?? english[key] ?? chinese[key] ?? key.rawValue
    }

    static func hasTranslation(_ key: Key, language: AppUILanguage) -> Bool {
        switch language {
        case .zhHans: chinese[key] != nil
        case .english: english[key] != nil
        case .japanese: japanese[key] != nil
        }
    }

    // MARK: - 简体中文

    private static let chinese: [Key: String] = [
        .copied: "已复制",
        .copyTranscript: "复制识别文字",
        .copyCurrentText: "复制当前文字",
        .settingsEllipsis: "设置…",
        .cancel: "取消",
        .done: "完成",
        .failed: "失败",
        .success: "完成",
        .close: "关闭",
        .enabled: "已启用",
        .disabled: "已关闭",
        .detailsInSettings: "详情见设置",
        .followSpokenLanguage: "随口述语言",

        .startRecording: "开始录音",
        .stopAndTranscribe: "停止并转写",
        .cancelTranscribe: "取消转写",
        .cancelFinalize: "取消收敛",
        .cancelStructure: "取消整理",
        .cancelTranslate: "取消翻译",
        .cancelOptimize: "取消优化",
        .cancelRoute: "取消路由",
        .outputLanguage: "输出语言",
        .promptOptimize: "Prompt 优化",
        .targetAgent: "目标 Agent",
        .moreOutputOptions: "更多输出选项",
        .useStructuredOutput: "使用结构化输出",
        .useEmoji: "使用 Emoji",
        .structureIntensity: "整理强度",
        .llmNotConfiguredASROnly: "LLM API 模式未配置，仅输出 ASR 原文",
        .testConnection: "测试连接",
        .testConnectionHelp: "同时探测 ASR 与翻译/LLM 模型是否可达",
        .stageTiming: "耗时统计",
        .stageTimingHelp: "查看各阶段耗时，并可导出 CSV / HTML",
        .tokenUsage: "Token 用量",
        .tokenUsageHelp: "查看语音转写与 LLM 后处理接口返回的实际 Usage",
        .quitApp: "退出 Vibe Voice OSS",
        .windowStageTiming: "阶段耗时报告",
        .windowTokenUsage: "Token 用量统计",

        .phaseIdle: "按快捷键开始，再按一次结束",
        .phaseIdleHotKey: "按 %@ 开始，再按一次结束",
        .phaseRecording: "正在录音…再按一次结束",
        .phaseRecordingHotKey: "正在录音…按 %@ 结束",
        .phaseRecordingMode: "正在录音（%@）…按 %@ 结束",
        .phaseFinalizing: "正在收敛识别…",
        .phaseTranscribing: "正在转写…",
        .phaseStructuring: "正在整理内容…",
        .phaseTranslating: "正在翻译…",
        .phaseOptimizing: "正在编译 Prompt…",
        .phaseRouting: "智能路由处理中…",
        .hudRecording: "录音中",
        .hudFinalizing: "收敛中",
        .hudTranscribing: "转写中",
        .hudStructuring: "整理中",
        .hudTranslating: "翻译中",
        .hudOptimizing: "输出 Prompt",
        .hudRouting: "智能路由",
        .hudCustomSystemPrompt: "自定义 System Prompt",
        .hudWaitingSpeak: "说点什么，字幕会出现在这里",
        .hudWaitingFinalizing: "正在收敛识别结果…",
        .hudWaitingTranscribing: "正在转写语音…",
        .hudWaitingStructuring: "正在整理内容格式…",
        .hudWaitingTranslating: "正在翻译内容…",
        .hudWaitingOptimizing: "正在编译 Prompt…",
        .hudWaitingRouting: "智能路由处理中…",
        .hudWaitingFailed: "处理失败，请重试",
        .hudWaitingSuccess: "已完成",
        .hudListening: "正在聆听",
        .stopAndCancel: "停止并取消",
        .stopAccessibilityHint: "取消当前录音与后续处理",
        .copyAccessibilityHint: "复制当前正在显示的识别文字",

        .modeConversation: "对话",
        .modeEnglish: "英文",
        .modeStructured: "结构化",
        .modePrompt: "Prompt",
        .modeSmartRoute: "智能路由",
        .modeConversationCaption: "按输出语言处理（翻译 / 原样）",
        .modeEnglishCaption: "直接翻译为英文，不改变默认输出语言",
        .modeStructuredCaption: "结构化整理（沿用整理强度与 Emoji 开关）",
        .modePromptCaption: "按 Prompt 规则编译到目标 Agent",
        .modeSmartRouteCaption: "自定义 System Prompt 全权决定输出",
        .pressHotKey: "按 %@",
        .toggleHotKeyHint: "%@（按一次开始，再按一次结束）",

        .streamingBatch: "批处理",
        .streamingSSE: "结果流式（SSE）",
        .streamingDuplex: "双工 Streaming",
        .streamingBatchCaption: "录音时仍显示实时字幕；停录后用整段 WAV 做最终转写。",
        .streamingSSECaption: "录音时显示实时字幕；停录后整段上传，若服务端支持 SSE 则渐进出最终结果。",
        .streamingDuplexCaption: "录音过程中推送 PCM 并像字幕一样显示识别文字；优先 WebSocket，否则重叠窗伪流式。",

        .asrIntegrated: "集成模式 · 本地原生",
        .asrAPI: "API 模式 · OpenAI 兼容",
        .asrIntegratedCaption: "默认使用 WhisperKit 本地转写；Qwen3-ASR 需选择已下载的 MLX 模型目录；不需要 ASR API 服务。",
        .asrAPICaption: "连接 oMLX 或远端 OpenAI-compatible /v1/audio/transcriptions 服务。",
        .engineQwenCaption: "Swift 原生 MLX 推理，无 Python 运行时；需要选择已下载的 Qwen3-ASR MLX 模型目录。",
        .engineWhisperCaption: "使用 WhisperKit/Core ML，本地自动下载并缓存所选 WhisperKit 模型。",
        .llmDisabled: "关闭",
        .llmAPI: "API 模式",
        .llmDisabledCaption: "仅输出 ASR 原文；翻译、整理和 Prompt 编译不会运行。",
        .llmAPICaption: "通过 OpenAI-compatible Chat Completions API 执行翻译、整理和 Prompt 编译。",
        .transcodeASR: "ASR 标准 · 16 kHz 单声道 WAV",
        .transcodeArchive: "存档 · 48 kHz 立体声 WAV",
        .transcodeASRCaption: "送给 oMLX 语音识别的默认规格。",
        .transcodeArchiveCaption: "高质量存档，不直接送 ASR。",

        .intensityAuto: "自动",
        .intensityClean: "轻度整理",
        .intensityUltraConcise: "超精简",
        .intensityStructured: "内容整理",
        .intensityRewrite: "深度整理",
        .intensityAutoCaption: "按字数自动选择轻度或内容整理",
        .intensityCleanCaption: "标点、错词、口头语与基本分段",
        .intensityUltraConciseCaption: "比内容整理更狠地压缩：只留关键要点",
        .intensityStructuredCaption: "重组为自然段落；仅当内容本身并列时才用清单",
        .intensityRewriteCaption: "严格条目化与层级结构，改写成正式文档表达",

        .promptTargetChat: "通用 Chat",
        .promptTargetResearch: "Deep Research",
        .promptTargetImage: "图像生成",
        .promptTargetChatCaption: "面向对话型 LLM 的自包含指令",
        .promptTargetCodexCaption: "面向 Codex：读仓、改文件、跑命令/测试",
        .promptTargetClaudeCaption: "面向 Claude Code：仓库级编码代理",
        .promptTargetGrokCaption: "面向 Grok 编码代理",
        .promptTargetResearchCaption: "面向深度调研：证据、来源、对比",
        .promptTargetImageCaption: "面向文生图：主体、构图、风格、约束",

        .captionASROnly: "仅转写原文",
        .captionDirectEnglish: "直接翻译 → English",
        .captionSmartRoute: "智能路由 · 自定义 System Prompt",

        .paneGeneral: "通用",
        .paneRecognition: "语音识别",
        .paneAudio: "音频转码",
        .paneTranslation: "翻译与整理",
        .panePrompt: "识别提示词",
        .paneShortcuts: "快捷键与权限",
        .panePerformance: "性能与耗时",
        .uiLanguage: "界面语言",
        .uiLanguageCaption: "只影响 App 界面文案，不影响识别语言或输出语言。",
        .mixedOutputStyle: "拼音混合输出",
        .mixedOutputStyleCaption: "输入法把拼音与英文专有名词拼成整行时的呈现方式；技术品牌始终保留英文。",
        .mixedOutputDeveloper: "开发者模式（术语留英文）",
        .mixedOutputSmartChinese: "智能中文（术语转中文）",
        .mixedOutputOriginal: "保持混排原样",
        .fuzzyPinyin: "模糊拼音（可选）",
        .fuzzyPinyinCaption: "默认关闭，按标准拼音区分平翘舌。开启后仅容错 n/l 与前后鼻音（in/ing 等），不会再混淆 z/zh、c/ch、s/sh。",
        .importProjectVocabulary: "导入当前仓库词汇",
        .importProjectVocabularyCaption: "从本机打开的 git 仓库抽取类名、函数名和分支名，写入共享纠正词库（带「来源」标记），同时服务拼音选词与语音 ASR/整理纠错。可手工编辑 TSV 的 aliases 列补充误辨。",
        .importProjectVocabularyDone: "已导入 %@ 条项目词汇（来源：项目导入）",
        .sharedCorrectionLexiconStatus: "共享纠正词库 %@ 条 · %@",
        .settingsASRMode: "ASR 模式",
        .settingsEngine: "识别引擎",
        .settingsModel: "模型",
        .settingsEndpoint: "接口地址",
        .settingsAPIKey: "API Key",
        .settingsInputDevice: "输入设备",
        .settingsLaunchAtLogin: "登录时启动",
        .settingsStreamingMode: "流式模式",
        .settingsDuplexWS: "双工 WebSocket",
        .settingsLLMBackend: "LLM 模式",
        .settingsLLMEndpoint: "LLM 接口",
        .settingsLLMModel: "LLM 模型",
        .settingsSystemPrompt: "System Prompt",
        .settingsTranscodeProfile: "转码规格",
        .settingsNormalize: "响度归一化",
        .settingsCheckASR: "检查本地 ASR",
        .settingsTestASR: "测试 ASR",
        .settingsTestTranslation: "测试翻译模型",
        .settingsCheckPermissions: "检查权限",
        .settingsOpenTiming: "打开耗时统计",
        .settingsQwenRepo: "Qwen 模型仓库",
        .settingsModelPath: "模型目录",
        .settingsWhisperKitModel: "WhisperKit 模型",
        .settingsPrepareModel: "准备模型",

        .latestTotal: "最近一次合计",
        .stageTimingEmptyCaption: "完成一次录音处理后，这里会显示各阶段耗时；也可导出 CSV / HTML。",
        .recognitionLanguage: "识别语言",
        .recognitionLanguageCaption: "常用：zh=中文，yue=粤语，en=English，auto=自动检测；Qwen3-ASR 会自动映射成模型需要的语言提示。",
        .modelNameMatchCaption: "模型名请与 oMLX / 远端已加载的 ASR 名称一致，可直接手输。",
        .liveCaptionCaption: "录音时会像字幕一样实时显示识别文字（重叠窗伪流式）。下方模式只影响停录后的最终收敛方式。",
        .streamingModeAPIOnlyCaption: "连不上时自动降级为重叠窗伪流式（仍走本机转写接口）。",
        .integratedNoStreamingCaption: "集成模式停录后直接在本机转写；实时字幕和 WebSocket 仅在 API 模式下可用。",
        .localAudioSpecCaption: "本地音频规格，不走远程 API。",
        .llmSystemPromptCaption: "翻译/整理/Prompt 编译时作为附加指令；⌘⇧G 智能路由时作为唯一系统指令。",
        .llmModelKeyCaption: "模型名请填写 oMLX / 兼容服务端已加载的 chat 模型；可留空后按需填写。API Key 保存在本机，仅限本地使用。",
        .llmFeaturesOffCaption: "关闭时只输出 ASR 原文，下面的翻译、整理和 Prompt 编译参数不会生效。",
        .emojiOnCaption: "结构化输出中可加入装饰性 Emoji。",
        .emojiOffCaption: "结构化输出不使用装饰性 Emoji。",
        .llmOnlyWhenConfiguredCaption: "翻译 / 结构化 / Prompt 编译只在 LLM API 模式且模型配置完整时启用，可与 ASR 完全不同。",
        .promptHintWordsCaption: "填写人名、项目名和技术词，使用中文逗号分隔。",
        .shortcutsToggleCaption: "全局快捷键均为「按一次开始，再按一次结束」。⌘⇧G 智能路由使用自定义 System Prompt 全权处理。",
        .bluetoothAudioCaption: "双蓝牙用法：输入选 DJI Mic（无听筒），播放输出保持耳机。App 开麦时会尽量把被 HFP 抢走的输出抢回耳机。",
        .prepareModel: "准备模型",
        .checkLocalASR: "检查本地 ASR",
        .openStageTimingReport: "打开耗时报告",
        .openTokenUsageReport: "打开 Token 统计",
        .voicePipeline: "Voice Pipeline（VAD 切段）",
        .voicePipelineCaption: "开启后按热键持续聆听，停顿会自动切段并显示字幕；结束时再按当前输出规则处理并粘贴。",
        .voicePipelineUnavailable: "Voice Pipeline 仅在集成模式下可用；当前为 API 模式，已强制关闭。",
        .qwenRepoCaption: "默认 mlx-community/Qwen3-ASR-0.6B-6bit；也可使用 4bit / 8bit 版本。",
        .currentModel: "当前模型：%@",
        .modelFilesCaption: "模型目录需包含 config.json、model.safetensors 及 tokenizer 文件。",
        .hfEndpointCaption: "直连 huggingface.co 不稳定时可填写镜像；留空使用官方源。",
        .apiKeyOptional: "API Key（未启用可留空）",
        .recognitionMode: "识别模式",
        .streamingFallbackCaption: "连接失败时自动降级为重叠窗伪流式。",
        .cancelDownload: "取消下载",
        .sampleRate: "采样率",
        .channels: "声道",
        .codec: "编码",
        .maxGain: "最大增益",
        .customPrompt: "自定义整理 / 输出 Prompt",
        .customPromptCaption: "用于规定信息结构、取舍和文案风格；整理会优先采纳最后一次明确的自我修正。",
        .outputLanguageCombination: "输出语言组合",
        .outputLanguageCombinationCaption: "原文和翻译可独立选择；最多选 3 种翻译语言，共最多 4 段输出。",
        .providerProfileCaption: "按模型名自动选择 Provider Profile：qwen → Qwen，nemotron → NVIDIA Nemotron，其余 → OpenAI 兼容。",
        .apiKeyStorageCaption: "API Key 保存在 macOS 钥匙串；无证书签名的临时构建会退回本机受限文件（权限 0600）。",
        .structuredEmojiCaptionOn: "分区标题会带修饰性 Emoji（如 ✅ 📌）。",
        .structuredEmojiCaptionOff: "默认不加 Emoji，只用短段与小标题。",
        .shortcutsCaption: "全局快捷键均为按一次开始、再按一次结束；⌘⇧G 使用自定义 System Prompt。",
        .recordingInput: "录音输入",
        .currentPlaybackOutput: "当前系统播放输出",
        .bluetoothRefresh: "刷新设备",
        .choose: "选择",
        .timingNoRecords: "暂无耗时记录",
        .timingNoRecordsCaption: "完成一次录音转写后，各阶段耗时会显示在这里。",
        .timingHeader: "阶段耗时报告",
        .timingLatest: "最近一次合计 %@ · %@",
        .timingDescription: "记录每次录音后的转写 / 整理 / 翻译 / Prompt 编译耗时",
        .timingActive: "计时中",
        .exportCSV: "导出 CSV…",
        .exportHTML: "导出 HTML…",
        .clearRecords: "清空记录",
        .exportTimingCSV: "导出阶段耗时 CSV",
        .exportTimingHTML: "导出阶段耗时 HTML",
        .exportCancelled: "已取消导出",
        .exportSuccess: "已导出：%@",
        .exportFailed: "导出失败：%@",
        .tokenUsageHeader: "Token 用量统计",
        .tokenUsageCaption: "仅统计接口实际返回的 usage；本地模型或未返回 usage 的接口不会估算。",
        .tokenNoData: "暂无用量数据",
        .tokenNoDataCaption: "完成一次返回 usage 的转写、整理、翻译或 Prompt 优化后会显示在这里。",
        .tokenCumulative: "累计",
        .tokenRecent: "最近请求",
        .tokenRecordCount: "共 %@ 次 API 用量记录",
        .tokenInput: "Input Token",
        .tokenCachedInput: "Cached Input Token（Input 明细）",
        .tokenOutput: "Output Token",
        .tokenReasoning: "Reasoning Token（Output 明细）",
        .tokenAudioInput: "Audio Input Token",
        .tokenAudioOutput: "Audio Output Token",
        .tokenAudioDuration: "Audio 时长",
        .tokenTotal: "Total Token",
        .stageRecording: "录音",
        .stageFinalizing: "收敛识别",
        .stageTranscribing: "转写",
        .stageStructuring: "整理",
        .stageTranslating: "翻译",
        .stageOptimizing: "输出 Prompt",
        .stagePaste: "写入输入框",
        .outcomeSuccess: "完成",
        .outcomeFailed: "失败",
        .outcomeCancelled: "已取消",
        .timingHTMLNoStage: "无阶段数据",
        .timingHTMLGenerated: "生成于 %@ · 共 %@ 次运行",
        .timingHTMLTotal: "合计",
        .timingHTMLResult: "结果",
        .timingHTMLTarget: "目标 Agent",
        .timingHTMLFirstPartial: "首 partial",
        .timingHTMLStage: "阶段",
        .timingHTMLMilliseconds: "毫秒",
        .timingHTMLDuration: "时长",
        .timingHTMLNoRecords: "暂无记录",
        .japaneseModelRequirement: "日语自然化输出需要 5.6 或更高版本的模型；当前模型未通过版本检查。",
        .japaneseNaturalCaption: "日语会按自然的母语文体整理（需要 5.6 或更高版本模型）。",

        .justNow: "刚刚",
        .recognitionComplete: "识别完成",
        .copyButtonTitle: "复制按钮",
        .reformatButtonTitle: "重新整理嘅按钮",

        .supersededByNewRecording: "新的录音覆盖了进行中的任务",
        .pasteFailedNoFocus: "处理成功，但无法写入当前输入框",
        .pasteFailedDetail: "处理成功，但无法写入：%@内容已复制，请手动粘贴。",
        .cancelled: "已取消",
        .cancelledPeriod: "已取消。",
        .checkingLocalASR: "正在检查本地 ASR…",
        .localASRFirstUseHint: "本地原生 ASR：首次使用可能需要下载或加载模型。",
        .localASRReady: "本地 ASR 已就绪",
        .localASRCheckFailed: "本地 ASR 检查失败：%@",
        .connectingASRAPI: "正在连接 ASR API…",
        .probingStreaming: "正在探测 API Streaming 能力…",
        .asrConnectOK: "ASR 连接成功",
        .asrConnectFailed: "ASR 连接失败：%@",
        .apiNoLocalModel: "API 模式不需要下载本地 ASR 模型",
        .preparingLocalASR: "正在准备本地 ASR 模型…",
        .prepareLocalASRFailed: "准备本地 ASR 失败：%@",
        .llmPostProcessOff: "翻译/整理/Prompt 编译已关闭",
        .configureLLMFirst: "请先配置 LLM API 地址和模型名",
        .connectingTranslation: "正在连接翻译模型…",
        .translationConnectFailed: "翻译连接失败：%@",
        .testingConnections: "正在测试连接…",
        .checkingNativeASR: "正在检查本地原生 ASR…",
        .localASROK: "本地 ASR 正常",
        .asrAPIOK: "ASR API 正常",
        .asrFailed: "ASR 失败：%@",
        .llmNotEnabled: "LLM 后处理未启用",
        .translationFailed: "翻译失败：%@",
        .enableLLMInSettings: "请先在翻译与整理中启用并配置 LLM API 模式",
        .reformatPasteFailed: "整理成功，但无法写入当前输入框",
        .reformatPasteFailedDetail: "整理成功，但无法写入：%@内容已复制，请手动粘贴。",
        .launchAtLoginNeedAllow: "需要在系统设置的登录项中允许 Vibe Voice OSS。",
        .launchAtLoginOn: "已启用",
        .launchAtLoginOff: "已关闭",
        .launchAtLoginFailed: "设置失败：%@",
        .accessibilityGranted: "辅助使用权限已授权，可以自动写入当前输入框。",
        .accessibilityPromptOpened: "已打开辅助使用授权提示；授权前会只复制到剪贴板，不会反复弹窗。",
        .structuredPrefix: "结构化：%@",
        .promptCompileArrow: "Prompt 编译 → %@（%@）",
        .cleartextEndpointWarning: "警告：明文 HTTP 远程端点",
        .vadBackendSilero: "Silero CoreML",
        .vadBackendEnergy: "能量 VAD（降级）",
        .vadEnergyFallbackDetail: "未找到 Silero CoreML 模型，语音管线正在使用能量检测降级方案：音乐、键盘声、风扇噪声都可能被判成人声。运行 scripts/prepare-silero-vad.sh 生成模型后重启应用。",
        .hfEndpointRejected: "该镜像地址无效或使用了远程明文 HTTP，已忽略，模型仍从默认 Hugging Face 端点下载。模型权重下载后会加载进本进程，篡改传输等同于决定应用运行什么代码，因此镜像必须走 HTTPS。",
        .cleartextEndpointDetail: "该地址不是 HTTPS，也不在本机回环地址上：音频与转写文本会以未加密方式在网络上传输。请改用 HTTPS，或把服务部署到本机。",
        .credentialsPlaintextWarning: "当前构建为 ad-hoc 签名，API Key 无法存入钥匙串，只能以明文保存在本机文件中（权限 0600）。请使用带证书签名的正式版本以启用钥匙串存储。",
        .shortcutTaken: "已被占用",
        .shortcutsUnavailableDetail: "标记为「已被占用」的快捷键已被其他应用注册，按下不会有任何反应。退出占用它的应用（常见于 Raycast、Alfred、输入法等），然后重新打开设置即可重新注册。",
        .errInsecureEndpoint: "为保护 API Key，远程明文 HTTP 接口不可用；请改用 HTTPS，或仅在本机回环地址使用 HTTP。",
        .errMicrophoneDenied: "没有麦克风权限，请在系统设置中允许 Vibe Voice OSS 使用麦克风。",
        .errDeviceUnavailable: "找不到录音设备“%@”。请确认它仍然连接，或在设置中重新选择。",
        .errDeviceCannotSelect: "无法使用录音设备“%@”（Core Audio %d）。",
        .errNoSamples: "没有录到有效音频。",
        .errNoAudibleSignal: "没有从“%@”检测到声音。请检查麦克风是否静音、发射器是否连接，或在系统声音设置中切换输入设备。",
        .errInvalidInputFormat: "录音设备“%@”尚未就绪（采样率无效）。请稍候再试，或在设置中重新选择麦克风。",
        .errTapInstallFailed: "无法开始使用“%@”录音（输入格式不兼容）。请尝试重新插拔设备，或先在系统声音设置中选中该麦克风后再试。",
        .errASRInvalidEndpoint: "oMLX 接口地址无效。",
        .errASRServer: "oMLX 返回 HTTP %d：%@",
        .errASRInvalidResponse: "oMLX 返回了无法解析的响应。",
        .errASREmptyText: "识别完成，但返回文本为空。",
        .errASRTimedOut: "转写超过 30 秒，已自动中断。",
        .errASRLocalTimedOut: "本地 ASR 超过 %d 分钟仍未完成，已自动中断。首次下载或加载模型可能较慢，请检查网络、模型名称或本地模型目录后重试。",
        .errASRLocalRuntime: "本地 ASR 运行失败：%@",
        .errLLMInvalidEndpoint: "翻译接口地址无效。",
        .errLLMServer: "翻译模型返回 HTTP %d：%@",
        .errLLMInvalidResponse: "翻译模型返回了无法解析的响应。",
        .errLLMEmptyText: "翻译完成，但返回文本为空。",
        .errLLMTimedOut: "LLM 处理超过 %d 秒，已自动中断。长内容可缩短后重试，或检查模型的限流与上下文限制。",
        .errFormatInvalidEndpoint: "结构化整理接口地址无效。",
        .errFormatServer: "整理模型返回 HTTP %d：%@",
        .errFormatInvalidResponse: "整理模型返回了无法解析的响应。",
        .errFormatEmptyText: "整理完成，但返回文本为空。",
        .errFormatTimedOut: "结构化整理超过 %d 秒，已自动中断。请检查模型限流、上下文长度或缩短输入后重试。",
        .errPromptCompile: "Prompt 编译失败：%@",
        .errPromptIRInvalid: "Prompt IR 无法解析：%@",
        .errPromptIREmpty: "Prompt IR 为空，无法编译。",
        .errAccessibilityDenied: "需要辅助功能权限才能向当前光标插入文字。请在系统设置 → 隐私与安全 → 辅助功能中关闭再重新打开 Vibe Voice OSS 的开关。",
        .errCannotCreateEvent: "无法生成文本输入事件。",
        .errVADModelMissing: "Silero VAD 模型未准备：%@。请运行 scripts/prepare-silero-vad.sh。",
        .errVADModelLoadFailed: "Silero VAD 加载失败：%@",
        .errPipelineNeedsLocalASR: "Voice Pipeline 仅支持本地 ASR（WhisperKit 或 Qwen3-ASR），请将 ASR 模式设为「集成」。",
        .errPipelineEmptyText: "本地 ASR 未返回文本。",
    ]

    // MARK: - English

    private static let english: [Key: String] = [
        .copied: "Copied",
        .copyTranscript: "Copy transcript",
        .copyCurrentText: "Copy current text",
        .settingsEllipsis: "Settings…",
        .cancel: "Cancel",
        .done: "Done",
        .failed: "Failed",
        .success: "Done",
        .close: "Close",
        .enabled: "On",
        .disabled: "Off",
        .detailsInSettings: "See Settings for details",
        .followSpokenLanguage: "Match spoken language",

        .startRecording: "Start recording",
        .stopAndTranscribe: "Stop & transcribe",
        .cancelTranscribe: "Cancel transcription",
        .cancelFinalize: "Cancel finalizing",
        .cancelStructure: "Cancel formatting",
        .cancelTranslate: "Cancel translation",
        .cancelOptimize: "Cancel Prompt compile",
        .cancelRoute: "Cancel smart route",
        .outputLanguage: "Output language",
        .promptOptimize: "Prompt optimize",
        .targetAgent: "Target agent",
        .moreOutputOptions: "More output options",
        .useStructuredOutput: "Structured output",
        .useEmoji: "Use emoji",
        .structureIntensity: "Structure intensity",
        .llmNotConfiguredASROnly: "LLM API not configured — ASR text only",
        .testConnection: "Test connection",
        .testConnectionHelp: "Probe ASR and translation/LLM reachability",
        .stageTiming: "Timing",
        .stageTimingHelp: "Inspect stage timings; export CSV / HTML",
        .tokenUsage: "Token usage",
        .tokenUsageHelp: "Usage reported by ASR and LLM APIs",
        .quitApp: "Quit Vibe Voice OSS",
        .windowStageTiming: "Stage Timing Report",
        .windowTokenUsage: "Token Usage",

        .phaseIdle: "Press a shortcut to start, press again to stop",
        .phaseIdleHotKey: "Press %@ to start, press again to stop",
        .phaseRecording: "Recording… press again to stop",
        .phaseRecordingHotKey: "Recording… press %@ to stop",
        .phaseRecordingMode: "Recording (%@)… press %@ to stop",
        .phaseFinalizing: "Finalizing recognition…",
        .phaseTranscribing: "Transcribing…",
        .phaseStructuring: "Formatting…",
        .phaseTranslating: "Translating…",
        .phaseOptimizing: "Compiling Prompt…",
        .phaseRouting: "Smart routing…",
        .hudRecording: "Recording",
        .hudFinalizing: "Finalizing",
        .hudTranscribing: "Transcribing",
        .hudStructuring: "Formatting",
        .hudTranslating: "Translating",
        .hudOptimizing: "Prompt",
        .hudRouting: "Smart route",
        .hudCustomSystemPrompt: "Custom system prompt",
        .hudWaitingSpeak: "Start speaking — captions appear here",
        .hudWaitingFinalizing: "Finalizing recognition…",
        .hudWaitingTranscribing: "Transcribing audio…",
        .hudWaitingStructuring: "Formatting content…",
        .hudWaitingTranslating: "Translating…",
        .hudWaitingOptimizing: "Compiling Prompt…",
        .hudWaitingRouting: "Smart routing…",
        .hudWaitingFailed: "Something went wrong — try again",
        .hudWaitingSuccess: "Done",
        .hudListening: "Listening",
        .stopAndCancel: "Stop and cancel",
        .stopAccessibilityHint: "Cancel recording and processing",
        .copyAccessibilityHint: "Copy the text currently shown",

        .modeConversation: "Conversation",
        .modeEnglish: "English",
        .modeStructured: "Structured",
        .modePrompt: "Prompt",
        .modeSmartRoute: "Smart route",
        .modeConversationCaption: "Follow output language (translate / keep)",
        .modeEnglishCaption: "Translate to English without changing the default output language",
        .modeStructuredCaption: "Structured cleanup (uses intensity & emoji settings)",
        .modePromptCaption: "Compile into the target agent Prompt",
        .modeSmartRouteCaption: "Custom system prompt decides the full output",
        .pressHotKey: "Press %@",
        .toggleHotKeyHint: "%@ (press once to start, again to stop)",

        .streamingBatch: "Batch",
        .streamingSSE: "Result stream (SSE)",
        .streamingDuplex: "Duplex streaming",
        .streamingBatchCaption: "Live captions while recording; final pass on the full WAV after stop.",
        .streamingSSECaption: "Live captions while recording; upload full audio after stop and fade in SSE finals when supported.",
        .streamingDuplexCaption: "Push PCM while recording for caption-like text; WebSocket first, overlapping-window fallback otherwise.",

        .asrIntegrated: "Integrated · on-device",
        .asrAPI: "API · OpenAI-compatible",
        .asrIntegratedCaption: "WhisperKit on-device by default; Qwen3-ASR needs a downloaded MLX model folder. No ASR API server required.",
        .asrAPICaption: "Connect to oMLX or a remote OpenAI-compatible /v1/audio/transcriptions endpoint.",
        .engineQwenCaption: "Native Swift MLX inference (no Python). Select a downloaded Qwen3-ASR MLX model folder.",
        .engineWhisperCaption: "WhisperKit / Core ML — downloads and caches the selected WhisperKit model locally.",
        .llmDisabled: "Off",
        .llmAPI: "API",
        .llmDisabledCaption: "ASR text only; translation, formatting, and Prompt compile stay off.",
        .llmAPICaption: "Run translation, formatting, and Prompt compile via an OpenAI-compatible Chat Completions API.",
        .transcodeASR: "ASR standard · 16 kHz mono WAV",
        .transcodeArchive: "Archive · 48 kHz stereo WAV",
        .transcodeASRCaption: "Default format for speech recognition.",
        .transcodeArchiveCaption: "High-quality archive; not sent directly to ASR.",

        .intensityAuto: "Auto",
        .intensityClean: "Light cleanup",
        .intensityUltraConcise: "Ultra concise",
        .intensityStructured: "Restructure",
        .intensityRewrite: "Deep rewrite",
        .intensityAutoCaption: "Pick light cleanup or restructure from length automatically",
        .intensityCleanCaption: "Punctuation, typos, filler words, and basic paragraphs",
        .intensityUltraConciseCaption: "Compress harder than restructure — keep only key points",
        .intensityStructuredCaption: "Rebuild as natural paragraphs; lists only when the content is genuinely parallel",
        .intensityRewriteCaption: "Strict itemization and hierarchy, rewritten as polished document prose",

        .promptTargetChat: "General chat",
        .promptTargetResearch: "Deep Research",
        .promptTargetImage: "Image generation",
        .promptTargetChatCaption: "Self-contained instructions for conversational LLMs",
        .promptTargetCodexCaption: "For Codex: read repo, edit files, run commands/tests",
        .promptTargetClaudeCaption: "For Claude Code: repo-scale coding agent",
        .promptTargetGrokCaption: "For Grok coding agent",
        .promptTargetResearchCaption: "For deep research: evidence, sources, comparisons",
        .promptTargetImageCaption: "For text-to-image: subject, composition, style, constraints",

        .captionASROnly: "ASR text only",
        .captionDirectEnglish: "Translate → English",
        .captionSmartRoute: "Smart route · custom system prompt",

        .paneGeneral: "General",
        .paneRecognition: "Speech recognition",
        .paneAudio: "Audio transcode",
        .paneTranslation: "Translate & format",
        .panePrompt: "Recognition prompt",
        .paneShortcuts: "Shortcuts & privacy",
        .panePerformance: "Performance",
        .uiLanguage: "Interface language",
        .uiLanguageCaption: "Affects App UI only — not recognition language or output language.",
        .mixedOutputStyle: "Mixed pinyin output",
        .mixedOutputStyleCaption: "How the input method renders a full line that mixes pinyin with English proper nouns. Brand names always stay English.",
        .mixedOutputDeveloper: "Developer (keep terms in English)",
        .mixedOutputSmartChinese: "Smart Chinese (translate common terms)",
        .mixedOutputOriginal: "Keep mixed style",
        .fuzzyPinyin: "Fuzzy pinyin (optional)",
        .fuzzyPinyinCaption: "Off by default — standard Hanyu Pinyin keeps z/zh, c/ch, s/sh distinct. When on, only n/l and nasal finals (in/ing…) are tolerated.",
        .importProjectVocabulary: "Import project vocabulary",
        .importProjectVocabularyCaption: "Scan the open git repository for class, function, and branch names into the shared correction lexicon (with a source tag) for both pinyin and voice ASR/cleanup. Edit the TSV aliases column to add misrecognition variants.",
        .importProjectVocabularyDone: "Imported %@ project terms (source: project)",
        .sharedCorrectionLexiconStatus: "Shared correction lexicon: %@ entries · %@",
        .settingsASRMode: "ASR mode",
        .settingsEngine: "Engine",
        .settingsModel: "Model",
        .settingsEndpoint: "Endpoint",
        .settingsAPIKey: "API Key",
        .settingsInputDevice: "Input device",
        .settingsLaunchAtLogin: "Launch at login",
        .settingsStreamingMode: "Streaming mode",
        .settingsDuplexWS: "Duplex WebSocket",
        .settingsLLMBackend: "LLM mode",
        .settingsLLMEndpoint: "LLM endpoint",
        .settingsLLMModel: "LLM model",
        .settingsSystemPrompt: "System prompt",
        .settingsTranscodeProfile: "Transcode profile",
        .settingsNormalize: "Loudness normalize",
        .settingsCheckASR: "Check local ASR",
        .settingsTestASR: "Test ASR",
        .settingsTestTranslation: "Test translation model",
        .settingsCheckPermissions: "Check permissions",
        .settingsOpenTiming: "Open timing stats",
        .settingsQwenRepo: "Qwen model repo",
        .settingsModelPath: "Model folder",
        .settingsWhisperKitModel: "WhisperKit model",
        .settingsPrepareModel: "Prepare model",

        .latestTotal: "Latest total",
        .stageTimingEmptyCaption: "After a recording finishes, stage timings appear here. You can also export CSV / HTML.",
        .recognitionLanguage: "Recognition language",
        .recognitionLanguageCaption: "Common: zh=Chinese, yue=Cantonese, en=English, auto=detect. Qwen3-ASR maps these to model language hints.",
        .modelNameMatchCaption: "Use the same ASR model name as oMLX / your remote server.",
        .liveCaptionCaption: "Live captions while recording (overlapping-window pseudo-stream). The mode below only affects finalization after stop.",
        .streamingModeAPIOnlyCaption: "Falls back to overlapping-window pseudo-stream if the socket is unreachable.",
        .integratedNoStreamingCaption: "Integrated mode finalizes on-device after stop. Live captions / WebSocket are API-mode only.",
        .localAudioSpecCaption: "Local audio format — not a remote API setting.",
        .llmSystemPromptCaption: "Extra instruction for translate / format / Prompt compile. For ⌘⇧G smart route it is the sole system prompt.",
        .llmModelKeyCaption: "Enter the chat model name loaded on your server. API keys stay on this Mac.",
        .llmFeaturesOffCaption: "When off, only ASR text is emitted; translate / format / Prompt options below are ignored.",
        .emojiOnCaption: "Allow decorative emoji in structured output.",
        .emojiOffCaption: "No decorative emoji in structured output.",
        .llmOnlyWhenConfiguredCaption: "Translate / structure / Prompt compile run only when LLM API mode is fully configured (can differ from ASR).",
        .promptHintWordsCaption: "Names, projects, and jargon — separate with Chinese commas.",
        .shortcutsToggleCaption: "Global shortcuts are press-to-start / press-to-stop. ⌘⇧G smart route uses your custom system prompt.",
        .bluetoothAudioCaption: "Dual-Bluetooth tip: pick DJI Mic as input; keep headphones for playback. While armed, the app tries to reclaim output stolen by HFP.",
        .prepareModel: "Prepare model",
        .checkLocalASR: "Check local ASR",
        .openStageTimingReport: "Open timing report",
        .openTokenUsageReport: "Open token usage",
        .voicePipeline: "Voice Pipeline (VAD segments)",
        .voicePipelineCaption: "Hold the shortcut to listen continuously; pauses create caption segments. Final output follows the selected rules.",
        .voicePipelineUnavailable: "Voice Pipeline is available only in Integrated mode; it is disabled in API mode.",
        .qwenRepoCaption: "Default: mlx-community/Qwen3-ASR-0.6B-6bit; 4bit / 8bit variants are also supported.",
        .currentModel: "Current model: %@",
        .modelFilesCaption: "The folder must contain config.json, model.safetensors, and tokenizer files.",
        .hfEndpointCaption: "Use a mirror if huggingface.co is unreliable; leave blank for the official source.",
        .apiKeyOptional: "API Key (optional when disabled)",
        .recognitionMode: "Recognition mode",
        .streamingFallbackCaption: "Falls back to overlapping-window pseudo-streaming if the connection fails.",
        .cancelDownload: "Cancel download",
        .sampleRate: "Sample rate",
        .channels: "Channels",
        .codec: "Codec",
        .maxGain: "Maximum gain",
        .customPrompt: "Custom cleanup / output Prompt",
        .customPromptCaption: "Defines structure, omissions, and writing style; the last explicit correction takes priority.",
        .outputLanguageCombination: "Output language combination",
        .outputLanguageCombinationCaption: "Choose the original and up to 3 translation languages independently, for at most 4 sections.",
        .providerProfileCaption: "Provider Profile is selected by model name: qwen → Qwen, nemotron → NVIDIA Nemotron, otherwise OpenAI-compatible.",
        .apiKeyStorageCaption: "API keys are stored in the macOS Keychain; ad-hoc signed builds fall back to a restricted local file (mode 0600).",
        .structuredEmojiCaptionOn: "Section headings may include decorative emoji (for example ✅ 📌).",
        .structuredEmojiCaptionOff: "No decorative emoji; use short paragraphs and headings.",
        .shortcutsCaption: "Global shortcuts toggle start/stop; ⌘⇧G uses the custom System Prompt.",
        .recordingInput: "Recording input",
        .currentPlaybackOutput: "Current system playback output",
        .bluetoothRefresh: "Refresh devices",
        .choose: "Choose",
        .timingNoRecords: "No timing records",
        .timingNoRecordsCaption: "Stage timings appear here after a recording is transcribed.",
        .timingHeader: "Stage Timing Report",
        .timingLatest: "Latest total %@ · %@",
        .timingDescription: "Timing for transcription / formatting / translation / Prompt compile after each recording",
        .timingActive: "Timing",
        .exportCSV: "Export CSV…",
        .exportHTML: "Export HTML…",
        .clearRecords: "Clear records",
        .exportTimingCSV: "Export stage timing CSV",
        .exportTimingHTML: "Export stage timing HTML",
        .exportCancelled: "Export cancelled",
        .exportSuccess: "Exported: %@",
        .exportFailed: "Export failed: %@",
        .tokenUsageHeader: "Token Usage",
        .tokenUsageCaption: "Only provider-reported usage is shown; local models and responses without usage are not estimated.",
        .tokenNoData: "No usage data",
        .tokenNoDataCaption: "Usage appears after a transcription, formatting, translation, or Prompt request returns usage.",
        .tokenCumulative: "Cumulative",
        .tokenRecent: "Recent requests",
        .tokenRecordCount: "%@ API usage records",
        .tokenInput: "Input Token",
        .tokenCachedInput: "Cached Input Token (input detail)",
        .tokenOutput: "Output Token",
        .tokenReasoning: "Reasoning Token (output detail)",
        .tokenAudioInput: "Audio Input Token",
        .tokenAudioOutput: "Audio Output Token",
        .tokenAudioDuration: "Audio duration",
        .tokenTotal: "Total Token",
        .stageRecording: "Recording",
        .stageFinalizing: "Finalizing",
        .stageTranscribing: "Transcribing",
        .stageStructuring: "Formatting",
        .stageTranslating: "Translating",
        .stageOptimizing: "Prompt compile",
        .stagePaste: "Insert into field",
        .outcomeSuccess: "Done",
        .outcomeFailed: "Failed",
        .outcomeCancelled: "Cancelled",
        .timingHTMLNoStage: "No stage data",
        .timingHTMLGenerated: "Generated %@ · %@ runs",
        .timingHTMLTotal: "Total",
        .timingHTMLResult: "Result",
        .timingHTMLTarget: "Target agent",
        .timingHTMLFirstPartial: "First partial",
        .timingHTMLStage: "Stage",
        .timingHTMLMilliseconds: "Milliseconds",
        .timingHTMLDuration: "Duration",
        .timingHTMLNoRecords: "No records",
        .japaneseModelRequirement: "Natural Japanese output requires model version 5.6 or later; the current model did not pass the version check.",
        .japaneseNaturalCaption: "Japanese output uses natural native-language editing (requires model version 5.6 or later).",

        .justNow: "Just now",
        .recognitionComplete: "Recognition complete",
        .copyButtonTitle: "Copy",
        .reformatButtonTitle: "Reformat",

        .supersededByNewRecording: "A new recording replaced the in-progress job",
        .pasteFailedNoFocus: "Done, but couldn’t insert into the focused field",
        .pasteFailedDetail: "Done, but couldn’t insert: %@. Text is copied — paste manually.",
        .cancelled: "Cancelled",
        .cancelledPeriod: "Cancelled.",
        .checkingLocalASR: "Checking local ASR…",
        .localASRFirstUseHint: "On-device ASR: first use may download or load a model.",
        .localASRReady: "Local ASR ready",
        .localASRCheckFailed: "Local ASR check failed: %@",
        .connectingASRAPI: "Connecting to ASR API…",
        .probingStreaming: "Probing API streaming…",
        .asrConnectOK: "ASR connected",
        .asrConnectFailed: "ASR connection failed: %@",
        .apiNoLocalModel: "API mode doesn’t need a local ASR model download",
        .preparingLocalASR: "Preparing local ASR model…",
        .prepareLocalASRFailed: "Preparing local ASR failed: %@",
        .llmPostProcessOff: "Translate / format / Prompt compile is off",
        .configureLLMFirst: "Configure the LLM API URL and model name first",
        .connectingTranslation: "Connecting to translation model…",
        .translationConnectFailed: "Translation connection failed: %@",
        .testingConnections: "Testing connections…",
        .checkingNativeASR: "Checking on-device ASR…",
        .localASROK: "Local ASR OK",
        .asrAPIOK: "ASR API OK",
        .asrFailed: "ASR failed: %@",
        .llmNotEnabled: "LLM post-processing is off",
        .translationFailed: "Translation failed: %@",
        .enableLLMInSettings: "Enable and configure LLM API mode under Translate & format first",
        .reformatPasteFailed: "Formatted, but couldn’t insert into the focused field",
        .reformatPasteFailedDetail: "Formatted, but couldn’t insert: %@. Text is copied — paste manually.",
        .launchAtLoginNeedAllow: "Allow Vibe Voice OSS in Login Items in System Settings.",
        .launchAtLoginOn: "On",
        .launchAtLoginOff: "Off",
        .launchAtLoginFailed: "Couldn’t update setting: %@",
        .accessibilityGranted: "Accessibility is granted — text can be inserted into the focused field.",
        .accessibilityPromptOpened: "Opened the Accessibility prompt. Until granted, text is copied only (no repeat prompts).",
        .structuredPrefix: "Structured: %@",
        .promptCompileArrow: "Prompt compile → %@ (%@)",
        .cleartextEndpointWarning: "Warning: clear-text HTTP endpoint",
        .vadBackendSilero: "Silero CoreML",
        .vadBackendEnergy: "Energy VAD (degraded)",
        .vadEnergyFallbackDetail: "No Silero CoreML model was found, so the voice pipeline is running on energy detection: music, keystrokes and fan noise can all register as speech. Run scripts/prepare-silero-vad.sh, then restart the app.",
        .hfEndpointRejected: "This mirror is invalid or uses remote clear-text HTTP, so it was ignored and models still download from the default Hugging Face host. Downloaded weights are loaded into this process, so tampering with the transfer decides what the app runs — mirrors must use HTTPS.",
        .cleartextEndpointDetail: "This address is neither HTTPS nor on the loopback interface: audio and transcripts travel over the network unencrypted. Use HTTPS, or run the service locally.",
        .credentialsPlaintextWarning: "This build is ad-hoc signed, so API keys cannot go into the Keychain. They are stored in a local file in clear text (mode 0600). Use a certificate-signed build to enable Keychain storage.",
        .shortcutTaken: "taken",
        .shortcutsUnavailableDetail: "The shortcuts marked \"taken\" are already registered by another application, so pressing them does nothing. Quit whatever holds them (Raycast, Alfred and input methods are the usual culprits), then reopen Settings to register them again.",
        .errInsecureEndpoint: "Remote clear-text HTTP endpoints are refused so the API key is not sent in the open. Use HTTPS, or keep HTTP for loopback addresses only.",
        .errMicrophoneDenied: "No microphone permission. Allow Vibe Voice OSS to use the microphone in System Settings.",
        .errDeviceUnavailable: "Input device “%@” is gone. Check that it is still connected, or pick another one in Settings.",
        .errDeviceCannotSelect: "Couldn’t use input device “%@” (Core Audio %d).",
        .errNoSamples: "No usable audio was recorded.",
        .errNoAudibleSignal: "Nothing was heard from “%@”. Check whether the mic is muted or the transmitter is connected, or switch input device in Sound settings.",
        .errInvalidInputFormat: "Input device “%@” is not ready yet (invalid sample rate). Try again in a moment, or pick another microphone in Settings.",
        .errTapInstallFailed: "Couldn’t start recording from “%@” (incompatible input format). Try reconnecting the device, or select it in Sound settings first.",
        .errASRInvalidEndpoint: "The oMLX endpoint URL is not valid.",
        .errASRServer: "oMLX returned HTTP %d: %@",
        .errASRInvalidResponse: "oMLX returned a response that could not be parsed.",
        .errASREmptyText: "Transcription finished but returned no text.",
        .errASRTimedOut: "Transcription took longer than 30 seconds and was stopped.",
        .errASRLocalTimedOut: "Local ASR did not finish within %d minutes and was stopped. The first download or model load can be slow — check the network, the model name and the local model directory, then retry.",
        .errASRLocalRuntime: "Local ASR failed: %@",
        .errLLMInvalidEndpoint: "The translation endpoint URL is not valid.",
        .errLLMServer: "The translation model returned HTTP %d: %@",
        .errLLMInvalidResponse: "The translation model returned a response that could not be parsed.",
        .errLLMEmptyText: "Translation finished but returned no text.",
        .errLLMTimedOut: "The LLM took longer than %d seconds and was stopped. Shorten long input and retry, or check the model’s rate limit and context window.",
        .errFormatInvalidEndpoint: "The formatting endpoint URL is not valid.",
        .errFormatServer: "The formatting model returned HTTP %d: %@",
        .errFormatInvalidResponse: "The formatting model returned a response that could not be parsed.",
        .errFormatEmptyText: "Formatting finished but returned no text.",
        .errFormatTimedOut: "Formatting took longer than %d seconds and was stopped. Check the model’s rate limit and context window, or shorten the input and retry.",
        .errPromptCompile: "Prompt compilation failed: %@",
        .errPromptIRInvalid: "Prompt IR could not be parsed: %@",
        .errPromptIREmpty: "Prompt IR is empty, nothing to compile.",
        .errAccessibilityDenied: "Accessibility permission is required to insert text at the cursor. In System Settings → Privacy & Security → Accessibility, turn the Vibe Voice OSS switch off and back on.",
        .errCannotCreateEvent: "Couldn’t create the text input event.",
        .errVADModelMissing: "The Silero VAD model is not prepared: %@. Run scripts/prepare-silero-vad.sh.",
        .errVADModelLoadFailed: "Silero VAD failed to load: %@",
        .errPipelineNeedsLocalASR: "Voice Pipeline only supports local ASR (WhisperKit or Qwen3-ASR). Set the ASR mode to Integrated.",
        .errPipelineEmptyText: "Local ASR returned no text.",
    ]

    // MARK: - 日本語

    private static let japanese: [Key: String] = [
        .copied: "コピーしました",
        .copyTranscript: "認識テキストをコピー",
        .copyCurrentText: "現在のテキストをコピー",
        .settingsEllipsis: "設定…",
        .cancel: "キャンセル",
        .done: "完了",
        .failed: "失敗",
        .success: "完了",
        .close: "閉じる",
        .enabled: "オン",
        .disabled: "オフ",
        .detailsInSettings: "詳しくは設定を確認してください",
        .followSpokenLanguage: "話し言葉に合わせる",
        .startRecording: "録音を開始",
        .stopAndTranscribe: "停止して文字起こし",
        .cancelTranscribe: "文字起こしをキャンセル",
        .cancelFinalize: "認識結果の確定をキャンセル",
        .cancelStructure: "整理をキャンセル",
        .cancelTranslate: "翻訳をキャンセル",
        .cancelOptimize: "Prompt の最適化をキャンセル",
        .cancelRoute: "スマートルートをキャンセル",
        .outputLanguage: "出力言語",
        .promptOptimize: "Prompt を最適化",
        .targetAgent: "対象 Agent",
        .moreOutputOptions: "その他の出力設定",
        .useStructuredOutput: "構造化して出力",
        .useEmoji: "Emoji を使う",
        .structureIntensity: "整理の強さ",
        .llmNotConfiguredASROnly: "LLM API 未設定のため、ASR 原文のみ出力します",
        .testConnection: "接続をテスト",
        .testConnectionHelp: "ASR と翻訳/LLM の接続を確認します",
        .stageTiming: "処理時間",
        .stageTimingHelp: "各工程の時間を確認し、CSV / HTML に書き出します",
        .tokenUsage: "Token 使用量",
        .tokenUsageHelp: "ASR と LLM API が返した使用量を確認します",
        .quitApp: "Vibe Voice OSS を終了",
        .windowStageTiming: "処理時間レポート",
        .windowTokenUsage: "Token 使用量",
        .phaseIdle: "ショートカットで開始し、もう一度押して停止",
        .phaseIdleHotKey: "%@ で開始し、もう一度押して停止",
        .phaseRecording: "録音中…もう一度押して停止",
        .phaseRecordingHotKey: "録音中…%@ で停止",
        .phaseRecordingMode: "録音中（%@）…%@ で停止",
        .phaseFinalizing: "認識結果を確定中…",
        .phaseTranscribing: "文字起こし中…",
        .phaseStructuring: "内容を整理中…",
        .phaseTranslating: "翻訳中…",
        .phaseOptimizing: "Prompt を作成中…",
        .phaseRouting: "スマートルーティング中…",
        .hudRecording: "録音中",
        .hudFinalizing: "確定中",
        .hudTranscribing: "文字起こし中",
        .hudStructuring: "整理中",
        .hudTranslating: "翻訳中",
        .hudOptimizing: "Prompt",
        .hudRouting: "スマートルート",
        .hudCustomSystemPrompt: "カスタム System Prompt",
        .hudWaitingSpeak: "話してください。ここに字幕が表示されます",
        .hudWaitingFinalizing: "認識結果を確定中…",
        .hudWaitingTranscribing: "音声を文字起こし中…",
        .hudWaitingStructuring: "内容の形式を整理中…",
        .hudWaitingTranslating: "翻訳中…",
        .hudWaitingOptimizing: "Prompt を作成中…",
        .hudWaitingRouting: "スマートルーティング中…",
        .hudWaitingFailed: "処理に失敗しました。もう一度お試しください",
        .hudWaitingSuccess: "完了",
        .hudListening: "聞き取り中",
        .stopAndCancel: "停止してキャンセル",
        .stopAccessibilityHint: "録音と処理をキャンセル",
        .copyAccessibilityHint: "表示中のテキストをコピー",
        .modeConversation: "会話",
        .modeEnglish: "英語",
        .modeStructured: "構造化",
        .modePrompt: "Prompt",
        .modeSmartRoute: "スマートルート",
        .modeConversationCaption: "出力言語に合わせて翻訳または原文のまま処理",
        .modeEnglishCaption: "既定の出力言語は変えず、英語へ翻訳",
        .modeStructuredCaption: "整理の強さと Emoji 設定に従って整形",
        .modePromptCaption: "対象 Agent 向けの Prompt に変換",
        .modeSmartRouteCaption: "カスタム System Prompt が出力全体を決定",
        .pressHotKey: "%@ を押してください",
        .toggleHotKeyHint: "%@（1回で開始、もう1回で停止）",
        .streamingBatch: "バッチ",
        .streamingSSE: "結果ストリーム（SSE）",
        .streamingDuplex: "双方向ストリーミング",
        .streamingBatchCaption: "録音中は字幕を表示し、停止後に WAV 全体を最終処理します。",
        .streamingSSECaption: "録音中は字幕を表示し、停止後に音声全体を送信して SSE 結果を段階的に表示します。",
        .streamingDuplexCaption: "録音中に PCM を送り、WebSocket を優先して字幕のように表示します。",
        .asrIntegrated: "統合 · デバイス上",
        .asrAPI: "API · OpenAI 互換",
        .asrIntegratedCaption: "既定は WhisperKit による端末内処理。Qwen3-ASR は MLX モデルが必要で、ASR API サーバーは不要です。",
        .asrAPICaption: "oMLX またはリモートの OpenAI 互換 /v1/audio/transcriptions に接続します。",
        .engineQwenCaption: "Python 不要の Swift 製 MLX 推論。ダウンロード済みの Qwen3-ASR MLX フォルダを選択します。",
        .engineWhisperCaption: "WhisperKit / Core ML を使い、選択したモデルを端末内にダウンロードしてキャッシュします。",
        .llmDisabled: "オフ",
        .llmAPI: "API",
        .llmDisabledCaption: "ASR 原文のみを出力し、翻訳・整理・Prompt 作成は行いません。",
        .llmAPICaption: "OpenAI 互換 Chat Completions API で翻訳・整理・Prompt 作成を行います。",
        .transcodeASR: "ASR 標準 · 16 kHz モノラル WAV",
        .transcodeArchive: "アーカイブ · 48 kHz ステレオ WAV",
        .transcodeASRCaption: "音声認識に使う既定の形式です。",
        .transcodeArchiveCaption: "高音質保存用です。ASR へは直接送信しません。",
        .intensityAuto: "自動",
        .intensityClean: "軽く整理",
        .intensityUltraConcise: "極めて簡潔",
        .intensityStructured: "構成を整理",
        .intensityRewrite: "大きく書き直す",
        .intensityAutoCaption: "長さに応じて軽い整理か構成整理を選びます",
        .intensityCleanCaption: "句読点、誤り、フィラー、基本的な段落分けを整えます",
        .intensityUltraConciseCaption: "要点だけを残して、構成整理より強く圧縮します",
        .intensityStructuredCaption: "自然な段落に組み直します。並列の内容のときだけリストにします",
        .intensityRewriteCaption: "厳密な箇条書きと階層構造で、正式な文書に書き直します",
        .promptTargetChat: "一般チャット",
        .promptTargetResearch: "Deep Research",
        .promptTargetImage: "画像生成",
        .promptTargetChatCaption: "会話型 LLM 向けの自己完結した指示",
        .promptTargetCodexCaption: "Codex 向け：リポジトリを読み、編集し、コマンド/テストを実行",
        .promptTargetClaudeCaption: "Claude Code 向け：リポジトリ規模のコーディング Agent",
        .promptTargetGrokCaption: "Grok コーディング Agent 向け",
        .promptTargetResearchCaption: "深掘り調査向け：根拠、出典、比較",
        .promptTargetImageCaption: "画像生成向け：主題、構図、スタイル、制約",
        .captionASROnly: "ASR 原文のみ",
        .captionDirectEnglish: "翻訳 → English",
        .captionSmartRoute: "スマートルート · カスタム System Prompt",
        .paneGeneral: "一般",
        .paneRecognition: "音声認識",
        .paneAudio: "音声変換",
        .paneTranslation: "翻訳と整理",
        .panePrompt: "認識用 Prompt",
        .paneShortcuts: "ショートカットとプライバシー",
        .panePerformance: "パフォーマンス",
        .uiLanguage: "インターフェース言語",
        .uiLanguageCaption: "App の表示だけを変更します。認識言語と出力言語には影響しません。",
        .mixedOutputStyle: "拼音＋英語の出力",
        .mixedOutputStyleCaption: "拼音と英語固有名詞を一行に組み立てるときの表示方法。ブランド名は常に英語のままです。",
        .mixedOutputDeveloper: "開発者モード（用語は英語）",
        .mixedOutputSmartChinese: "スマート中国語（用語を翻訳）",
        .mixedOutputOriginal: "混在スタイルを維持",
        .fuzzyPinyin: "曖昧拼音（任意）",
        .fuzzyPinyinCaption: "既定はオフ。標準拼音どおり平舌/翹舌を区別します。オン時も n/l と前後鼻音のみで、z/zh・c/ch・s/sh は混ぜません。",
        .importProjectVocabulary: "プロジェクト語彙を取り込む",
        .importProjectVocabularyCaption: "開いている git リポジトリからクラス名、関数名、ブランチ名を共有訂正語彙（出典付き）へ書き込み、拼音と音声 ASR/整理の両方で使います。TSV の aliases 列で誤認識を追加できます。",
        .importProjectVocabularyDone: "%@ 件のプロジェクト語彙を取り込みました（出典：プロジェクト）",
        .sharedCorrectionLexiconStatus: "共有訂正語彙 %@ 件 · %@",
        .settingsASRMode: "ASR モード",
        .settingsEngine: "エンジン",
        .settingsModel: "モデル",
        .settingsEndpoint: "エンドポイント",
        .settingsAPIKey: "API Key",
        .settingsInputDevice: "入力デバイス",
        .settingsLaunchAtLogin: "ログイン時に起動",
        .settingsStreamingMode: "ストリーミングモード",
        .settingsDuplexWS: "双方向 WebSocket",
        .settingsLLMBackend: "LLM モード",
        .settingsLLMEndpoint: "LLM エンドポイント",
        .settingsLLMModel: "LLM モデル",
        .settingsSystemPrompt: "System Prompt",
        .settingsTranscodeProfile: "変換プロファイル",
        .settingsNormalize: "音量を正規化",
        .settingsCheckASR: "ローカル ASR を確認",
        .settingsTestASR: "ASR をテスト",
        .settingsTestTranslation: "翻訳モデルをテスト",
        .settingsCheckPermissions: "権限を確認",
        .settingsOpenTiming: "処理時間を開く",
        .settingsQwenRepo: "Qwen モデルリポジトリ",
        .settingsModelPath: "モデルフォルダ",
        .settingsWhisperKitModel: "WhisperKit モデル",
        .settingsPrepareModel: "モデルを準備",
        .latestTotal: "最新の合計",
        .stageTimingEmptyCaption: "録音処理が完了すると各工程の時間が表示されます。CSV / HTML にも書き出せます。",
        .recognitionLanguage: "認識言語",
        .recognitionLanguageCaption: "例：zh=中国語、yue=広東語、en=英語、auto=自動検出。Qwen3-ASR 用の言語指定に変換します。",
        .modelNameMatchCaption: "oMLX またはリモートサーバーに読み込んだ ASR モデル名と一致させてください。",
        .liveCaptionCaption: "録音中は字幕のように表示します。下のモードは停止後の最終処理だけに適用されます。",
        .streamingModeAPIOnlyCaption: "接続できない場合は重複ウィンドウ方式に切り替えます。",
        .integratedNoStreamingCaption: "統合モードでは停止後に端末内で確定します。ライブ字幕と WebSocket は API モードのみ対応します。",
        .localAudioSpecCaption: "端末内で使う音声形式です。リモート API の設定ではありません。",
        .llmSystemPromptCaption: "翻訳・整理・Prompt 作成への追加指示です。⌘⇧G のスマートルートでは唯一の System Prompt になります。",
        .llmModelKeyCaption: "サーバーに読み込んだ chat モデル名を入力してください。API Key はこの Mac に保存されます。",
        .llmFeaturesOffCaption: "オフにすると ASR 原文だけを出力し、下の翻訳・整理・Prompt 設定は無効になります。",
        .emojiOnCaption: "構造化出力に装飾用 Emoji を許可します。",
        .emojiOffCaption: "構造化出力に装飾用 Emoji を使いません。",
        .llmOnlyWhenConfiguredCaption: "翻訳・整理・Prompt 作成は、LLM API とモデルが完全に設定されている場合だけ実行します。",
        .promptHintWordsCaption: "人名、プロジェクト名、専門用語を入力し、日本語の読点で区切ります。",
        .shortcutsToggleCaption: "グローバルショートカットは1回で開始、もう1回で停止します。⌘⇧G はカスタム System Prompt で処理します。",
        .bluetoothAudioCaption: "Bluetooth を2台使う場合は DJI Mic を入力、ヘッドホンを出力にします。HFP に奪われた出力はできるだけ戻します。",
        .prepareModel: "モデルを準備",
        .checkLocalASR: "ローカル ASR を確認",
        .openStageTimingReport: "処理時間レポートを開く",
        .openTokenUsageReport: "Token 使用量を開く",
        .justNow: "たった今",
        .recognitionComplete: "認識完了",
        .copyButtonTitle: "コピー",
        .reformatButtonTitle: "整理し直す",
        .supersededByNewRecording: "新しい録音によって処理中のタスクが置き換えられました",
        .pasteFailedNoFocus: "完了しましたが、フォーカス中の入力欄へ挿入できませんでした",
        .pasteFailedDetail: "挿入できませんでした：%@。テキストはコピー済みです。手動で貼り付けてください。",
        .cancelled: "キャンセルしました",
        .cancelledPeriod: "キャンセルしました。",
        .checkingLocalASR: "ローカル ASR を確認中…",
        .localASRFirstUseHint: "端末内 ASR は初回利用時にモデルのダウンロードまたは読み込みが必要な場合があります。",
        .localASRReady: "ローカル ASR の準備ができました",
        .localASRCheckFailed: "ローカル ASR の確認に失敗：%@",
        .connectingASRAPI: "ASR API に接続中…",
        .probingStreaming: "API のストリーミング対応を確認中…",
        .asrConnectOK: "ASR に接続しました",
        .asrConnectFailed: "ASR 接続に失敗：%@",
        .apiNoLocalModel: "API モードではローカル ASR モデルは不要です",
        .preparingLocalASR: "ローカル ASR モデルを準備中…",
        .prepareLocalASRFailed: "ローカル ASR の準備に失敗：%@",
        .llmPostProcessOff: "翻訳・整理・Prompt 作成はオフです",
        .configureLLMFirst: "先に LLM API の URL とモデル名を設定してください",
        .connectingTranslation: "翻訳モデルに接続中…",
        .translationConnectFailed: "翻訳接続に失敗：%@",
        .testingConnections: "接続をテスト中…",
        .checkingNativeASR: "端末内 ASR を確認中…",
        .localASROK: "ローカル ASR は正常です",
        .asrAPIOK: "ASR API は正常です",
        .asrFailed: "ASR に失敗：%@",
        .llmNotEnabled: "LLM の後処理はオフです",
        .translationFailed: "翻訳に失敗：%@",
        .enableLLMInSettings: "先に「翻訳と整理」で LLM API を有効にして設定してください",
        .reformatPasteFailed: "整理しましたが、フォーカス中の入力欄へ挿入できませんでした",
        .reformatPasteFailedDetail: "整理結果を挿入できませんでした：%@。テキストはコピー済みです。",
        .launchAtLoginNeedAllow: "システム設定のログイン項目で Vibe Voice OSS を許可してください。",
        .launchAtLoginOn: "オン",
        .launchAtLoginOff: "オフ",
        .launchAtLoginFailed: "設定を更新できませんでした：%@",
        .accessibilityGranted: "アクセシビリティが許可されています。フォーカス中の入力欄へ挿入できます。",
        .accessibilityPromptOpened: "アクセシビリティ設定を開きました。許可されるまではテキストのみコピーします。",
        .structuredPrefix: "構造化：%@",
        .promptCompileArrow: "Prompt 作成 → %@（%@）",
        .voicePipeline: "Voice Pipeline（VAD セグメント）",
        .voicePipelineCaption: "ショートカットで連続して聞き取り、無音で字幕を区切ります。終了時は選択した出力ルールで処理します。",
        .voicePipelineUnavailable: "Voice Pipeline は統合モードでのみ利用できます。API モードでは無効です。",
        .qwenRepoCaption: "既定は mlx-community/Qwen3-ASR-0.6B-6bit。4bit / 8bit 版も利用できます。",
        .currentModel: "現在のモデル：%@",
        .modelFilesCaption: "フォルダには config.json、model.safetensors、tokenizer ファイルが必要です。",
        .hfEndpointCaption: "huggingface.co が不安定な場合はミラーを指定し、空欄なら公式ソースを使います。",
        .apiKeyOptional: "API Key（オフの場合は任意）",
        .recognitionMode: "認識モード",
        .streamingFallbackCaption: "接続できない場合は重複ウィンドウ方式に切り替えます。",
        .cancelDownload: "ダウンロードをキャンセル",
        .sampleRate: "サンプルレート",
        .channels: "チャンネル",
        .codec: "コーデック",
        .maxGain: "最大ゲイン",
        .customPrompt: "カスタム整理 / 出力 Prompt",
        .customPromptCaption: "情報の構成、取捨選択、文章のスタイルを指定します。最後に明示した修正を優先します。",
        .outputLanguageCombination: "出力言語の組み合わせ",
        .outputLanguageCombinationCaption: "原文と最大3つの翻訳言語を個別に選択できます（最大4セクション）。",
        .providerProfileCaption: "モデル名で Provider Profile を選択します：qwen → Qwen、nemotron → NVIDIA Nemotron、それ以外は OpenAI 互換です。",
        .apiKeyStorageCaption: "API Key は macOS キーチェーンに保存します。ad-hoc 署名ビルドではローカルの制限付きファイル（パーミッション 0600）に保存します。",
        .structuredEmojiCaptionOn: "見出しに装飾用 Emoji（例：✅ 📌）を付けます。",
        .structuredEmojiCaptionOff: "装飾用 Emoji は使わず、短い段落と見出しだけにします。",
        .shortcutsCaption: "グローバルショートカットは1回で開始、もう1回で停止します。⌘⇧G はカスタム System Prompt を使います。",
        .recordingInput: "録音入力",
        .currentPlaybackOutput: "現在のシステム再生出力",
        .bluetoothRefresh: "デバイスを更新",
        .choose: "選択",
        .timingNoRecords: "処理時間の記録はありません",
        .timingNoRecordsCaption: "録音の文字起こしが完了すると、各工程の時間がここに表示されます。",
        .timingHeader: "処理時間レポート",
        .timingLatest: "最新の合計 %@ · %@",
        .timingDescription: "録音ごとの文字起こし / 整理 / 翻訳 / Prompt 作成の時間を記録します",
        .timingActive: "計測中",
        .exportCSV: "CSV を書き出す…",
        .exportHTML: "HTML を書き出す…",
        .clearRecords: "記録を消去",
        .exportTimingCSV: "処理時間を CSV に書き出す",
        .exportTimingHTML: "処理時間を HTML に書き出す",
        .exportCancelled: "書き出しをキャンセルしました",
        .exportSuccess: "書き出しました：%@",
        .exportFailed: "書き出しに失敗：%@",
        .tokenUsageHeader: "Token 使用量",
        .tokenUsageCaption: "API が実際に返した usage だけを表示します。端末内モデルや usage のない応答は推定しません。",
        .tokenNoData: "使用量データはありません",
        .tokenNoDataCaption: "usage を返す文字起こし、整理、翻訳、Prompt 処理が完了すると表示されます。",
        .tokenCumulative: "累計",
        .tokenRecent: "最近のリクエスト",
        .tokenRecordCount: "API 使用量の記録 %@ 件",
        .tokenInput: "Input Token",
        .tokenCachedInput: "Cached Input Token（入力詳細）",
        .tokenOutput: "Output Token",
        .tokenReasoning: "Reasoning Token（出力詳細）",
        .tokenAudioInput: "Audio Input Token",
        .tokenAudioOutput: "Audio Output Token",
        .tokenAudioDuration: "音声の長さ",
        .tokenTotal: "Total Token",
        .stageRecording: "録音",
        .stageFinalizing: "認識結果の確定",
        .stageTranscribing: "文字起こし",
        .stageStructuring: "整理",
        .stageTranslating: "翻訳",
        .stageOptimizing: "Prompt 作成",
        .stagePaste: "入力欄へ挿入",
        .outcomeSuccess: "完了",
        .outcomeFailed: "失敗",
        .outcomeCancelled: "キャンセル",
        .timingHTMLNoStage: "工程データなし",
        .timingHTMLGenerated: "%@ に生成 · %@ 回の実行",
        .timingHTMLTotal: "合計",
        .timingHTMLResult: "結果",
        .timingHTMLTarget: "対象 Agent",
        .timingHTMLFirstPartial: "最初の partial",
        .timingHTMLStage: "工程",
        .timingHTMLMilliseconds: "ミリ秒",
        .timingHTMLDuration: "時間",
        .timingHTMLNoRecords: "記録なし",
        .japaneseModelRequirement: "自然な日本語の出力にはバージョン 5.6 以上のモデルが必要です。現在のモデルはバージョン確認を通過しませんでした。",
        .japaneseNaturalCaption: "日本語は自然な母語の文体で整理します（バージョン 5.6 以上のモデルが必要です）。",
        .cleartextEndpointWarning: "警告: 平文 HTTP のリモートエンドポイント",
        .vadBackendSilero: "Silero CoreML",
        .vadBackendEnergy: "エネルギー VAD（縮退）",
        .vadEnergyFallbackDetail: "Silero CoreML モデルが見つからないため、音声パイプラインはエネルギー検出で動作しています。音楽・キー入力・ファンの音も音声と判定されることがあります。scripts/prepare-silero-vad.sh を実行してからアプリを再起動してください。",
        .hfEndpointRejected: "このミラーは無効か、リモートの平文 HTTP のため無視されました。モデルは既定の Hugging Face からダウンロードされます。ダウンロードした重みはこのプロセスに読み込まれるため、通信を改ざんされるとアプリが実行する内容を握られます。ミラーは HTTPS が必須です。",
        .cleartextEndpointDetail: "このアドレスは HTTPS でもループバックでもありません。音声と文字起こしが暗号化されずにネットワークを流れます。HTTPS を使うか、サービスをローカルで動かしてください。",
        .credentialsPlaintextWarning: "このビルドは ad-hoc 署名のため、API キーをキーチェーンに保存できません。ローカルファイルに平文（パーミッション 0600）で保存されます。キーチェーン保存には証明書で署名されたビルドを使用してください。",
        .shortcutTaken: "使用中",
        .shortcutsUnavailableDetail: "「使用中」と表示されたショートカットは他のアプリがすでに登録しているため、押しても何も起きません。占有しているアプリ（Raycast、Alfred、入力メソッドなど）を終了してから設定を開き直すと再登録されます。",
        .errInsecureEndpoint: "API キーを平文で送らないため、リモートの平文 HTTP エンドポイントは使用できません。HTTPS を使うか、HTTP はループバックアドレスに限定してください。",
        .errMicrophoneDenied: "マイクの権限がありません。システム設定で Vibe Voice OSS のマイク使用を許可してください。",
        .errDeviceUnavailable: "録音デバイス「%@」が見つかりません。接続を確認するか、設定で選び直してください。",
        .errDeviceCannotSelect: "録音デバイス「%@」を使用できません（Core Audio %d）。",
        .errNoSamples: "有効な音声が録音されませんでした。",
        .errNoAudibleSignal: "「%@」から音声を検出できませんでした。マイクのミュートや送信機の接続を確認するか、サウンド設定で入力デバイスを切り替えてください。",
        .errInvalidInputFormat: "録音デバイス「%@」はまだ準備できていません（サンプルレートが無効）。少し待って再試行するか、設定でマイクを選び直してください。",
        .errTapInstallFailed: "「%@」での録音を開始できません（入力フォーマットが非対応）。デバイスを接続し直すか、先にサウンド設定でそのマイクを選択してください。",
        .errASRInvalidEndpoint: "oMLX のエンドポイント URL が無効です。",
        .errASRServer: "oMLX が HTTP %d を返しました：%@",
        .errASRInvalidResponse: "oMLX が解析できない応答を返しました。",
        .errASREmptyText: "認識は完了しましたが、テキストが空です。",
        .errASRTimedOut: "文字起こしが 30 秒を超えたため中断しました。",
        .errASRLocalTimedOut: "ローカル ASR が %d 分経っても完了しないため中断しました。初回のダウンロードやモデル読み込みには時間がかかります。ネットワーク、モデル名、ローカルモデルのディレクトリを確認して再試行してください。",
        .errASRLocalRuntime: "ローカル ASR の実行に失敗しました：%@",
        .errLLMInvalidEndpoint: "翻訳エンドポイントの URL が無効です。",
        .errLLMServer: "翻訳モデルが HTTP %d を返しました：%@",
        .errLLMInvalidResponse: "翻訳モデルが解析できない応答を返しました。",
        .errLLMEmptyText: "翻訳は完了しましたが、テキストが空です。",
        .errLLMTimedOut: "LLM の処理が %d 秒を超えたため中断しました。長い入力は短くして再試行するか、モデルのレート制限とコンテキスト長を確認してください。",
        .errFormatInvalidEndpoint: "整形エンドポイントの URL が無効です。",
        .errFormatServer: "整形モデルが HTTP %d を返しました：%@",
        .errFormatInvalidResponse: "整形モデルが解析できない応答を返しました。",
        .errFormatEmptyText: "整形は完了しましたが、テキストが空です。",
        .errFormatTimedOut: "整形が %d 秒を超えたため中断しました。モデルのレート制限やコンテキスト長を確認するか、入力を短くして再試行してください。",
        .errPromptCompile: "プロンプトのコンパイルに失敗しました：%@",
        .errPromptIRInvalid: "プロンプト IR を解析できません：%@",
        .errPromptIREmpty: "プロンプト IR が空のためコンパイルできません。",
        .errAccessibilityDenied: "カーソル位置にテキストを挿入するにはアクセシビリティ権限が必要です。システム設定 → プライバシーとセキュリティ → アクセシビリティ で Vibe Voice OSS のスイッチをオフにしてからオンに戻してください。",
        .errCannotCreateEvent: "テキスト入力イベントを生成できません。",
        .errVADModelMissing: "Silero VAD モデルが準備されていません：%@。scripts/prepare-silero-vad.sh を実行してください。",
        .errVADModelLoadFailed: "Silero VAD の読み込みに失敗しました：%@",
        .errPipelineNeedsLocalASR: "Voice Pipeline はローカル ASR（WhisperKit または Qwen3-ASR）のみ対応しています。ASR モードを「統合」に設定してください。",
        .errPipelineEmptyText: "ローカル ASR がテキストを返しませんでした。",
    ]
}

/// Observable wrapper so SwiftUI refreshes when the UI language changes.
@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()

    @Published private(set) var language: AppUILanguage = .zhHans

    func apply(_ language: AppUILanguage) {
        guard self.language != language else {
            L10n.language = language
            return
        }
        L10n.language = language
        self.language = language
    }

    func t(_ key: L10n.Key) -> String { L10n.t(key) }

    func t(_ key: L10n.Key, _ arguments: CVarArg...) -> String {
        let format = L10n.string(key, language: language)
        return String(format: format, locale: language.locale, arguments: arguments)
    }
}
