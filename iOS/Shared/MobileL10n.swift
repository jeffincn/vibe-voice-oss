import Foundation

/// The UI language the app and the keyboard extension render in.
///
/// Unlike the macOS app there is no in-app picker: iOS users expect an app to
/// follow the language they chose for the device, and a keyboard extension has
/// no settings screen of its own to expose a picker in.
enum MobileUILanguage: String, CaseIterable, Sendable {
    case zhHans
    case english

    var locale: Locale {
        switch self {
        case .zhHans: Locale(identifier: "zh_Hans")
        case .english: Locale(identifier: "en")
        }
    }

    /// Maps a BCP-47 tag such as `zh-Hans-CN` or `en-GB` onto a catalog.
    /// Anything that is not Chinese falls back to English, which is the wider
    /// of the two catalogs in reach.
    static func resolve(id: String) -> MobileUILanguage {
        id.lowercased().hasPrefix("zh") ? .zhHans : .english
    }

    static func resolveFromSystem(
        preferred: [String] = Locale.preferredLanguages
    ) -> MobileUILanguage {
        guard let first = preferred.first else { return .english }
        return resolve(id: first)
    }
}

/// UI string catalog for the iOS targets, in the same shape as the macOS
/// `L10n`. Strings are held in code rather than a `.strings` bundle so that the
/// keyboard extension and the containing app read one catalog from one source
/// file, and so that `MobileL10nTests` can assert every key is translated.
enum MobileL10n {
    enum Key: String, CaseIterable {
        // MARK: Keyboard keys
        case keySpace
        case keyDelete
        case keyNewline
        case keyShift
        case keyCapsLock
        case keySwitchKeyboard
        case keyToggleLanguage
        case keyNumbersPlane
        case keySymbolsPlane
        case keyLettersPlane

        // MARK: Candidates
        case candidatePreviousPage
        case candidateNextPage
        case candidateAccessibility // %1$d index, %2$@ text

        // MARK: Keyboard status
        case pinyinDegradedBadge
        case pinyinDegradedStatus // %@ reason
        case resultReadyElsewhere
        case resultInserted
        case voiceKeyTitle // %@ mode
        case voiceKeyAccessibility // %@ mode
        case voiceKeyInsertTitle
        case voiceKeyInsertAccessibility
        case voiceModeMenuTitle
        case voiceModeSelected // %@ mode

        // MARK: Bridge status
        case bridgeStatusIdle
        case bridgeStatusRequested
        case bridgeStatusRecording
        case bridgeStatusProcessing
        case bridgeStatusReady
        case bridgeStatusConsumed
        case bridgeStatusFailed
        case bridgeOpenAppToRecord
        case bridgeInterrupted

        // MARK: Output modes and language toggle
        case languageChinese
        case languageEnglish
        case modeOriginal
        case modePolished
        case modeTranslate

        // MARK: Voice phases
        case phaseIdle
        case phaseRequestingPermission
        case phaseRecording
        case phaseProcessing
        case phasePreparingModel
        case phaseReady
        case phaseFailed // %@ message
        case phaseRecordingOnDevice
        case phaseProcessingMode // %@ mode
        case phaseReturnToKeyboard
        case microphoneDenied
        case prepareFailed
        case preparing
        case modelNotPrepared
        case modelUnloaded
        case recordingStoppedInBackground
        case recordingInterrupted
        case recordingRouteLost

        // MARK: ASR
        case asrNoAudio
        case asrNoText
        case asrModelLoaded // %@ model
        case asrModelWarmed // %@ model

        // MARK: Rime
        case rimeDictionaryMissing
        case rimeContainerUnavailable
        case rimeSectionTitle
        case rimeExperimental
        case rimeDeploying
        case rimeRedeploy
        case rimeFootnote
        case rimeReady
        case rimeFailed // %@ message
        case rimeLearningCleared

        // MARK: Home screen
        case homeHero
        case homeEnableKeyboardTitle
        case homeEnableKeyboardBody
        case homeBridgeTitle
        case homeBridgeBody
        case homeBridgeReset
        case homeOutputTitle
        case homeOutputBody
        case homeStartRecording
        case homeStopAndTranscribe
        case homeLocalModelTitle
        case homeLocalModelButton
        case homeLocalModelBody
        case homePrivacyTitle
        case homePrivacyBody
        case homePrivacyClearButton
        case homePrivacyClearBody
    }

    private final class LanguageBox: @unchecked Sendable {
        let lock = NSLock()
        var language = MobileUILanguage.resolveFromSystem()
    }

    private static let box = LanguageBox()

    static var language: MobileUILanguage {
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

    static func t(_ key: Key, _ arguments: any CVarArg...) -> String {
        let format = string(key, language: language)
        return String(format: format, locale: language.locale, arguments: arguments)
    }

    static func string(_ key: Key, language: MobileUILanguage) -> String {
        let table: [Key: String]
        switch language {
        case .zhHans: table = chinese
        case .english: table = english
        }
        return table[key] ?? english[key] ?? chinese[key] ?? key.rawValue
    }

    static func hasTranslation(_ key: Key, language: MobileUILanguage) -> Bool {
        switch language {
        case .zhHans: chinese[key] != nil
        case .english: english[key] != nil
        }
    }

    // MARK: - 简体中文

    private static let chinese: [Key: String] = [
        .keySpace: "空格",
        .keyDelete: "删除",
        .keyNewline: "换行",
        .keyShift: "上档",
        .keyCapsLock: "大写锁定",
        .keySwitchKeyboard: "切换键盘",
        .keyToggleLanguage: "中英切换",
        .keyNumbersPlane: "数字与符号",
        .keySymbolsPlane: "更多符号",
        .keyLettersPlane: "字母",

        .candidatePreviousPage: "上一页候选",
        .candidateNextPage: "下一页候选",
        .candidateAccessibility: "候选 %1$d：%2$@",

        .pinyinDegradedBadge: "⚠️ 拼音降级",
        .pinyinDegradedStatus: "拼音降级：%@",
        .resultReadyElsewhere: "结果已就绪，回到原输入框或点麦克风插入",
        .resultInserted: "已插入",
        .voiceKeyTitle: "🎙 %@",
        .voiceKeyAccessibility: "语音输入，%@模式",
        .voiceKeyInsertTitle: "🎙 插入",
        .voiceKeyInsertAccessibility: "插入已完成的语音结果",
        .voiceModeMenuTitle: "语音输出模式",
        .voiceModeSelected: "已选择%@模式",

        .bridgeStatusIdle: "待机",
        .bridgeStatusRequested: "已请求",
        .bridgeStatusRecording: "正在录音",
        .bridgeStatusProcessing: "正在处理",
        .bridgeStatusReady: "结果就绪",
        .bridgeStatusConsumed: "已插入",
        .bridgeStatusFailed: "失败",
        .bridgeOpenAppToRecord: "请打开 Vibe Voice 开始录音",
        .bridgeInterrupted: "上次语音任务被系统中断，请重新录音",

        .languageChinese: "中",
        .languageEnglish: "EN",
        .modeOriginal: "原文",
        .modePolished: "整理",
        .modeTranslate: "翻译",

        .phaseIdle: "待机",
        .phaseRequestingPermission: "请求麦克风权限",
        .phaseRecording: "正在录音",
        .phaseProcessing: "正在本地转写",
        .phasePreparingModel: "下载并预热模型",
        .phaseReady: "结果已发送到键盘",
        .phaseFailed: "失败：%@",
        .phaseRecordingOnDevice: "正在 iPhone 上录音",
        .phaseProcessingMode: "%@模式处理中",
        .phaseReturnToKeyboard: "可返回键盘插入",
        .microphoneDenied: "麦克风权限未开启",
        .prepareFailed: "准备失败",
        .preparing: "准备中",
        .modelNotPrepared: "尚未准备",
        .modelUnloaded: "已释放内存，模型保留在本机",
        .recordingStoppedInBackground: "应用切到后台，录音已停止",
        .recordingInterrupted: "录音被系统中断，请重新录音",
        .recordingRouteLost: "录音输入设备已断开，请重新录音",

        .asrNoAudio: "没有录到可识别的声音。",
        .asrNoText: "模型没有返回文字，请靠近麦克风后重试。",
        .asrModelLoaded: "WhisperKit %@ 已加载",
        .asrModelWarmed: "WhisperKit %@ 已预热",

        .rimeDictionaryMissing: "应用内缺少 Rime 拼音词库。",
        .rimeContainerUnavailable: "无法访问键盘共享容器。",
        .rimeSectionTitle: "Rime 全拼",
        .rimeExperimental: "实验性",
        .rimeDeploying: "正在部署词库…",
        .rimeRedeploy: "重新准备 Rime",
        .rimeFootnote: "首次启用键盘前，请至少打开一次主应用。词库部署完成后，键盘扩展直接复用共享数据，不在输入时执行维护任务。",
        .rimeReady: "已就绪",
        .rimeFailed: "失败：%@",
        .rimeLearningCleared: "已清除学习记录",

        .homeHero: "Rime 全拼与语音输入的移动端工作区。键盘提供字母、数字、符号、上档、候选翻页与语音键，中文标点由 Rime 转换为全角。",
        .homeEnableKeyboardTitle: "启用键盘",
        .homeEnableKeyboardBody: "设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → Vibe Voice。语音桥接需要“允许完全访问”；基础中英文输入将保持离线可用。",
        .homeBridgeTitle: "语音桥接",
        .homeBridgeBody: "iOS 不允许第三方键盘扩展直接使用麦克风。键盘发起请求后，请切到此页录音；转写完成再切回原输入框，结果会自动插入。",
        .homeBridgeReset: "重置",
        .homeOutputTitle: "输出",
        .homeOutputBody: "“翻译”使用 Whisper 的语音转英文能力；“整理”在设备上清理空白并补齐句末标点，不上传文本。",
        .homeStartRecording: "开始录音",
        .homeStopAndTranscribe: "停止并转写",
        .homeLocalModelTitle: "本地模型",
        .homeLocalModelButton: "下载并预热语音模型",
        .homeLocalModelBody: "应用进入后台且没有录音或转写任务时，会自动卸载模型释放内存；下载文件仍保留在设备上。",
        .homePrivacyTitle: "隐私与数据",
        .homePrivacyBody: "语音转写只在本机进行，不上传音频或文字。转写结果写入键盘共享容器，插入后立即删除；键盘的拼音学习记录保存在共享容器内，仅本机可读。",
        .homePrivacyClearButton: "清除共享数据与拼音学习记录",
        .homePrivacyClearBody: "清除后键盘会重新从零学习，已部署的词库不受影响。",
    ]

    // MARK: - English

    private static let english: [Key: String] = [
        .keySpace: "space",
        .keyDelete: "delete",
        .keyNewline: "return",
        .keyShift: "shift",
        .keyCapsLock: "caps lock",
        .keySwitchKeyboard: "next keyboard",
        .keyToggleLanguage: "Chinese or English",
        .keyNumbersPlane: "numbers and symbols",
        .keySymbolsPlane: "more symbols",
        .keyLettersPlane: "letters",

        .candidatePreviousPage: "previous candidates",
        .candidateNextPage: "more candidates",
        .candidateAccessibility: "Candidate %1$d: %2$@",

        .pinyinDegradedBadge: "⚠️ limited pinyin",
        .pinyinDegradedStatus: "Limited pinyin: %@",
        .resultReadyElsewhere: "Result ready. Return to the original field or tap the mic to insert.",
        .resultInserted: "Inserted",
        .voiceKeyTitle: "🎙 %@",
        .voiceKeyAccessibility: "Voice input, %@ mode",
        .voiceKeyInsertTitle: "🎙 Insert",
        .voiceKeyInsertAccessibility: "Insert the finished transcript",
        .voiceModeMenuTitle: "Voice output mode",
        .voiceModeSelected: "%@ mode selected",

        .bridgeStatusIdle: "Idle",
        .bridgeStatusRequested: "Requested",
        .bridgeStatusRecording: "Recording",
        .bridgeStatusProcessing: "Processing",
        .bridgeStatusReady: "Ready",
        .bridgeStatusConsumed: "Inserted",
        .bridgeStatusFailed: "Failed",
        .bridgeOpenAppToRecord: "Open Vibe Voice to start recording",
        .bridgeInterrupted: "The last voice task was interrupted. Please record again.",

        .languageChinese: "中",
        .languageEnglish: "EN",
        .modeOriginal: "Raw",
        .modePolished: "Tidy",
        .modeTranslate: "Translate",

        .phaseIdle: "Idle",
        .phaseRequestingPermission: "Requesting microphone access",
        .phaseRecording: "Recording",
        .phaseProcessing: "Transcribing on device",
        .phasePreparingModel: "Downloading and warming up the model",
        .phaseReady: "Result sent to the keyboard",
        .phaseFailed: "Failed: %@",
        .phaseRecordingOnDevice: "Recording on iPhone",
        .phaseProcessingMode: "Processing in %@ mode",
        .phaseReturnToKeyboard: "Return to the keyboard to insert",
        .microphoneDenied: "Microphone access is off",
        .prepareFailed: "Preparation failed",
        .preparing: "Preparing",
        .modelNotPrepared: "Not prepared yet",
        .modelUnloaded: "Memory released. The model stays on this device.",
        .recordingStoppedInBackground: "The app went to the background, so recording stopped.",
        .recordingInterrupted: "Recording was interrupted. Please record again.",
        .recordingRouteLost: "The audio input was disconnected. Please record again.",

        .asrNoAudio: "No recognisable audio was captured.",
        .asrNoText: "The model returned no text. Move closer to the microphone and try again.",
        .asrModelLoaded: "WhisperKit %@ loaded",
        .asrModelWarmed: "WhisperKit %@ warmed up",

        .rimeDictionaryMissing: "The Rime pinyin dictionary is missing from the app.",
        .rimeContainerUnavailable: "The shared keyboard container is unavailable.",
        .rimeSectionTitle: "Rime full pinyin",
        .rimeExperimental: "Experimental",
        .rimeDeploying: "Deploying the dictionary…",
        .rimeRedeploy: "Prepare Rime again",
        .rimeFootnote: "Open the app at least once before enabling the keyboard. Once the dictionary is deployed the extension reuses the shared data and runs no maintenance while you type.",
        .rimeReady: "Ready",
        .rimeFailed: "Failed: %@",
        .rimeLearningCleared: "Learning data cleared",

        .homeHero: "A mobile workspace for Rime full pinyin and voice input. The keyboard has letters, numbers, symbols, shift, candidate paging, and a voice key; Rime converts Chinese punctuation to its full-width form.",
        .homeEnableKeyboardTitle: "Enable the keyboard",
        .homeEnableKeyboardBody: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Vibe Voice. The voice bridge needs Allow Full Access; basic Chinese and English typing keeps working offline without it.",
        .homeBridgeTitle: "Voice bridge",
        .homeBridgeBody: "iOS does not let a third-party keyboard extension use the microphone. After the keyboard asks for dictation, switch here to record; when the transcript is ready, switch back to the original field and it is inserted for you.",
        .homeBridgeReset: "Reset",
        .homeOutputTitle: "Output",
        .homeOutputBody: "Translate uses Whisper's speech-to-English capability. Tidy trims whitespace and adds a closing full stop on device; neither uploads text.",
        .homeStartRecording: "Start recording",
        .homeStopAndTranscribe: "Stop and transcribe",
        .homeLocalModelTitle: "On-device model",
        .homeLocalModelButton: "Download and warm up the voice model",
        .homeLocalModelBody: "When the app goes to the background with no recording or transcription in flight, the model is unloaded to free memory. The downloaded files stay on the device.",
        .homePrivacyTitle: "Privacy and data",
        .homePrivacyBody: "Transcription runs entirely on this device; no audio or text is uploaded. Results are written to the keyboard's shared container and deleted as soon as they are inserted. The keyboard's pinyin learning data stays in that container and is readable only on this device.",
        .homePrivacyClearButton: "Clear shared data and pinyin learning",
        .homePrivacyClearBody: "The keyboard starts learning from scratch afterwards. The deployed dictionary is unaffected.",
    ]
}
