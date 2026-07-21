import Foundation

/// UI string catalog. LLM / ASR prompts stay in their original language.
enum L10n {
    enum Key: String {
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
        let table = language == .english ? english : chinese
        return table[key] ?? chinese[key] ?? key.rawValue
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
        .intensityStructuredCaption: "理解关系并重组为段落、清单或步骤",
        .intensityRewriteCaption: "压缩冗余并改写成正式文档表达",

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
        .intensityStructuredCaption: "Infer relationships and rebuild as paragraphs, lists, or steps",
        .intensityRewriteCaption: "Cut redundancy and rewrite as polished document prose",

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
