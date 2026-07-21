import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case finalizing
        case transcribing
        case structuring
        case translating
        case optimizing
        case routing
        case success(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle: L10n.t(.phaseIdle)
            case .recording: L10n.t(.phaseRecording)
            case .finalizing: L10n.t(.phaseFinalizing)
            case .transcribing: L10n.t(.phaseTranscribing)
            case .structuring: L10n.t(.phaseStructuring)
            case .translating: L10n.t(.phaseTranslating)
            case .optimizing: L10n.t(.phaseOptimizing)
            case .routing: L10n.t(.phaseRouting)
            case let .success(text): text
            case let .failed(message): message
            }
        }

        func label(hotKey: RecordingHotKey) -> String {
            switch self {
            case .idle: L10n.t(.phaseIdleHotKey, hotKey.label)
            case .recording: L10n.t(.phaseRecordingHotKey, hotKey.label)
            default: label
            }
        }

        func pipelineLabel(hotKey: RecordingHotKey) -> String {
            switch self {
            case .idle: "Voice Pipeline：按 \(hotKey.label) 开始聆听"
            case .recording: "聆听中…说话自动切段转写，再按 \(hotKey.label) 结束"
            case .transcribing: "正在转写切段…"
            case let .success(text): text
            case let .failed(message): message
            default: label
            }
        }

        func label(mode: RecordingOutputMode?) -> String {
            switch self {
            case .idle:
                return RecordingOutputMode.shortcutLegend
            case .recording:
                if let mode {
                    return L10n.t(.phaseRecordingMode, mode.label, mode.chordLabel)
                }
                return L10n.t(.phaseRecording)
            default:
                return label
            }
        }

        var symbol: String {
            switch self {
            case .idle, .success: "waveform"
            case .recording: "record.circle.fill"
            case .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing: "ellipsis.circle"
            case .failed: "exclamationmark.triangle"
            }
        }

        var isBusy: Bool {
            switch self {
            case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing: true
            default: false
            }
        }

        /// High-level HUD caption (animation window).
        var hudPrimary: String {
            switch self {
            case .recording: L10n.t(.hudRecording)
            case .finalizing: L10n.t(.hudFinalizing)
            case .transcribing: L10n.t(.hudTranscribing)
            case .structuring: L10n.t(.hudStructuring)
            case .translating: L10n.t(.hudTranslating)
            case .optimizing: L10n.t(.hudOptimizing)
            case .routing: L10n.t(.hudRouting)
            case .success: L10n.t(.success)
            case .failed: L10n.t(.failed)
            case .idle: ""
            }
        }

        /// HUD primary when Voice Pipeline mode is active.
        var pipelineHUDPrimary: String {
            switch self {
            case .recording: "聆听中"
            case .transcribing: "切段转写"
            case .success: "完成"
            case .failed: "失败"
            default: hudPrimary
            }
        }

        /// Whether this phase can show a nested engine / target sub-status.
        var showsHUDSecondary: Bool {
            if case .optimizing = self { return true }
            if case .routing = self { return true }
            return false
        }

        var drivesLiveAudioVisual: Bool {
            self == .recording
        }
    }

    /// Nested HUD line for Prompt compile — e.g. Codex / Claude Code.
    var hudSecondary: String? {
        guard phase.showsHUDSecondary else { return nil }
        if case .routing = phase { return L10n.t(.hudCustomSystemPrompt) }
        return settings.promptTarget.label
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var connectionMessage = ""
    @Published private(set) var capabilityMessage = ""
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var audioBands: AudioBands = .silent
    @Published private(set) var partialTranscript = ""
    @Published private(set) var stableTranscript = ""
    @Published private(set) var lastTranscript = ""
    @Published private(set) var transcriptCopied = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage = ""
    @Published private(set) var lastCapabilities = OMLXCapabilities.unknown
    let settings = AppSettings()
    let stageTiming = StageTimingStore()
    let tokenUsage = TokenUsageStore()

    var inputDeviceName: String { recorder.deviceName(for: settings.inputDeviceUID) }

    private let recorder = AudioRecorder()
    private let voicePipeline = SpeechPipelineCoordinator()
    private let client = TranscriptionClient()
    private var pipelineObservation: Task<Void, Never>?
    private let translator = TranslationClient()
    private let formatter = SemanticFormatterClient()
    private let hotKey: HotKeyManager
    private var inputTargetPID: pid_t?
    private lazy var recordingHUD = RecordingHUDController(appState: self)
    private lazy var resultBanner = ResultBannerController(appState: self)
    private var transcriptionTask: Task<Void, Never>?
    private var hotKeyIsDown = false
    /// Mode selected by the hotkey that started the current recording (nil = menu/settings).
    private var sessionOutputMode: RecordingOutputMode?
    /// Monotonic token so Latest-only discards superseded audio/LLM snapshots.
    private var processingGeneration = 0
    private var streamingSession: StreamingTranscriptionSession?
    private var lastPartialPublishAt = Date.distantPast
    private let partialPublishInterval: TimeInterval = 1.0 / 20.0
    /// Serializes start paths so overlapping ⌘⇧R / menu / permission probe cannot double-open the engine.
    private var isStartingRecording = false
    private var isStartingVoicePipeline = false
    /// True while an open Voice Pipeline listen session owns the mic/HUD (independent of the settings toggle).
    private var voicePipelineSessionActive = false

    var phaseLabel: String {
        if settings.effectiveVoicePipelineEnabled {
            return phase.pipelineLabel(hotKey: settings.recordingHotKey)
        }
        return phase.label(mode: sessionOutputMode)
    }

    private struct ProcessingSnapshot {
        let wav: Data?
        let transcript: String?
        let generation: Int
        let configuration: TranscriptionConfiguration
        let targetLanguage: TargetLanguage
        let promptOptimizeEnabled: Bool
        let structuredOutputEnabled: Bool
        let structuredEmojiEnabled: Bool
        let structureIntensity: StructureIntensity
        let smartRouteEnabled: Bool
        let translationConfiguration: TranslationConfiguration
        let promptOptimizeConfiguration: TranslationConfiguration
        let smartRouteConfiguration: TranslationConfiguration
        let chatEndpoint: String
        let languageModel: String
        let apiKey: String
        let streamingMode: StreamingMode
        let outputMode: RecordingOutputMode?
    }

    init() {
        hotKey = HotKeyManager()
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                // Snappier attack so speech spikes show immediately; still damp release a bit.
                let smoothing: Float = level > self.audioLevel ? 0.82 : 0.28
                self.audioLevel += (level - self.audioLevel) * smoothing
            }
        }
        recorder.onBands = { [weak self] bands in
            Task { @MainActor in
                self?.audioBands = bands
            }
        }
        recorder.onPCMFrame = { [weak self] frame in
            Task { @MainActor in
                self?.streamingSession?.appendPCM(frame)
            }
        }
        hotKey.onEvent = { [weak self] mode, event in
            Task { @MainActor in
                switch event {
                case .pressed:
                    guard let self, !self.hotKeyIsDown else { return }
                    self.hotKeyIsDown = true
                    if self.settings.effectiveVoicePipelineEnabled {
                        await self.toggleVoicePipeline()
                    } else if self.voicePipelineSessionActive {
                        // Settings toggle was turned off mid-session — tear down pipeline, don't
                        // call finishRecording() on an AudioRecorder that never started.
                        self.stopVoicePipeline()
                    } else if self.phase == .recording {
                        self.finishRecording()
                    } else {
                        await self.beginRecording(outputMode: mode)
                    }
                case .released:
                    self?.hotKeyIsDown = false
                }
            }
        }

        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        if settings.launchAtLogin && !launchAtLoginEnabled {
            Task { @MainActor in self.setLaunchAtLogin(true) }
        } else if settings.launchAtLogin && launchAtLoginEnabled {
            // Re-register so Login Items show the current CFBundleDisplayName after renames.
            Task { @MainActor in
                try? SMAppService.mainApp.unregister()
                try? SMAppService.mainApp.register()
                self.launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// Kept for Settings UI refresh after unrelated preference changes.
    func applyRecordingHotKeyFromSettings() {
        hotKey.registerAll()
        objectWillChange.send()
    }

    /// Toggle experimental Voice Pipeline (VAD → local ASR). No LLM / paste in this path.
    func toggleVoicePipeline() async {
        if isStartingVoicePipeline { return }

        // Stop only when actively listening (not while stuck on a start-failure screen).
        if voicePipeline.isListening {
            stopVoicePipeline()
            return
        }
        if case .failed = voicePipeline.state {
            stopVoicePipeline()
        }

        isStartingVoicePipeline = true
        defer { isStartingVoicePipeline = false }

        // Cancel any in-flight PTT work.
        if phase.isBusy {
            processingGeneration += 1
            transcriptionTask?.cancel()
            transcriptionTask = nil
            streamingSession?.cancel()
            streamingSession = nil
            recorder.cancel()
        }

        partialTranscript = ""
        stableTranscript = ""
        lastTranscript = ""
        transcriptCopied = false
        resultBanner.hide()
        phase = .transcribing // "starting" affordance while models/mic prepare
        recordingHUD.show()
        connectionMessage = "Voice Pipeline 正在启动…"
        NSSound(named: "Tink")?.play()

        pipelineObservation?.cancel()
        pipelineObservation = Task { @MainActor [weak self] in
            guard let self else { return }
            var lastState = self.voicePipeline.state
            var lastStatusAt = Date.distantPast
            while !Task.isCancelled {
                let state = self.voicePipeline.state
                let level = self.voicePipeline.audioLevel
                let bands = self.voicePipeline.audioBands
                if abs(level - self.audioLevel) > 0.01 {
                    self.audioLevel = level
                }
                if bands != self.audioBands {
                    self.audioBands = bands
                }
                if state != lastState {
                    lastState = state
                    self.applyVoicePipelineState(state)
                }
                let now = Date()
                if self.voicePipeline.isListening, now.timeIntervalSince(lastStatusAt) >= 1.0 {
                    lastStatusAt = now
                    let pct = Int((self.voicePipeline.lastSpeechProbability * 100).rounded())
                    self.connectionMessage = self.voicePipeline.vadUsesCoreML
                        ? "聆听中 · Silero 语音概率 \(pct)%"
                        : "聆听中 · VAD \(pct)% · 说完停半秒出字"
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        await voicePipeline.start(
            deviceUID: settings.inputDeviceUID,
            configuration: settings.configuration
        )
        applyVoicePipelineState(voicePipeline.state)
        if case let .failed(message) = voicePipeline.state {
            connectionMessage = message
        } else if voicePipeline.isListening {
            connectionMessage = voicePipeline.vadUsesCoreML
                ? "Voice Pipeline 聆听中（Silero CoreML）"
                : "Voice Pipeline 聆听中（能量 VAD；可运行 prepare-silero-vad.sh 启用 CoreML）"
        }
    }

    func stopVoicePipeline() {
        pipelineObservation?.cancel()
        pipelineObservation = nil
        voicePipeline.stop()
        isStartingVoicePipeline = false
        voicePipelineSessionActive = false
        audioLevel = 0
        audioBands = .silent
        phase = .idle
        connectionMessage = ""
        recordingHUD.hide()
    }

    /// Called when Settings turns Voice Pipeline off (or switches to API mode).
    func handleVoicePipelineSettingChanged(enabled: Bool) {
        if !enabled, voicePipelineSessionActive || isStartingVoicePipeline || voicePipeline.isListening {
            stopVoicePipeline()
        }
    }

    private func applyVoicePipelineState(_ state: SpeechPipelineState) {
        switch state {
        case .idle:
            // Don't hide a start-failure message that AppState already pinned.
            if case .failed = phase { return }
            phase = .idle
            recordingHUD.hide()
        case .listening, .speechDetected, .speaking:
            // Stay on recording for the whole open session — avoid success↔recording flicker.
            phase = .recording
            recordingHUD.show()
        case .processing:
            phase = .transcribing
        case let .completed(text):
            // Accumulate segments; keep HUD in listening/recording (do not bounce through .success).
            if lastTranscript.isEmpty {
                lastTranscript = text
            } else if !lastTranscript.contains(text) || !lastTranscript.hasSuffix(text) {
                lastTranscript += "\n" + text
            }
            partialTranscript = lastTranscript
            stableTranscript = lastTranscript
            phase = .recording
            recordingHUD.show()
        case let .failed(message):
            // Segment ASR hiccups stay quiet if we are still listening; only pin hard start failures.
            if voicePipeline.isListening {
                connectionMessage = "切段转写失败：\(message)"
                phase = .recording
                recordingHUD.show()
            } else {
                phase = .failed(message)
                connectionMessage = message
                recordingHUD.show()
            }
        }
    }

    func beginRecording(outputMode: RecordingOutputMode? = nil) async {
        guard !isStartingRecording else { return }
        if case .recording = phase { return }

        isStartingRecording = true
        defer { isStartingRecording = false }

        switch phase {
        case .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing:
            // Latest-only: drop in-flight inference and any expired snapshot.
            processingGeneration += 1
            transcriptionTask?.cancel()
            transcriptionTask = nil
            streamingSession?.cancel()
            streamingSession = nil
            if stageTiming.hasActiveSession {
                stageTiming.finishSession(outcome: .superseded, message: "新的录音覆盖了进行中的任务")
            }
        default:
            break
        }

        sessionOutputMode = outputMode

        if let application = NSWorkspace.shared.frontmostApplication,
           application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            inputTargetPID = application.processIdentifier
        }
        do {
            try await recorder.start(deviceUID: settings.inputDeviceUID)
            let promptLabel: String?
            switch outputMode {
            case .prompt:
                promptLabel = settings.llmFeaturesAvailable ? settings.promptTarget.label : nil
            case .smartRoute:
                promptLabel = nil
            case .none:
                promptLabel = settings.llmFeaturesAvailable && settings.promptOptimizeEnabled
                    ? settings.promptTarget.label
                    : nil
            case .conversation, .english, .structured:
                promptLabel = nil
            }
            stageTiming.beginSession(promptTarget: promptLabel)
            stageTiming.enter(.recording)
            phase = .recording
            audioLevel = 0
            audioBands = .silent
            lastTranscript = ""
            partialTranscript = ""
            stableTranscript = ""
            transcriptCopied = false
            resultBanner.hide()
            recordingHUD.show()
            NSSound(named: "Tink")?.play()

            // Always run live captions while recording (subtitle UX), regardless of finalization mode.
            partialTranscript = ""
            let session = StreamingTranscriptionSession(
                onUpdate: { [weak self] accumulator in
                    self?.publishAccumulator(accumulator)
                },
                onFirstPartial: { [weak self] in
                    self?.stageTiming.markFirstPartial()
                },
                onUsage: { [weak self] usage in
                    guard let self else { return }
                    self.tokenUsage.record(
                        usage,
                        stage: .transcription,
                        model: self.settings.configuration.model
                    )
                }
            )
            streamingSession = session
            if settings.asrBackend == .api {
                let wsURL = settings.streamingMode == .duplexStreaming
                    ? URL(string: settings.streamingWSURL)
                    : nil
                await session.open(
                    configuration: settings.configuration,
                    streamingWSURL: wsURL
                )
            } else {
                await session.openLocal(configuration: settings.configuration)
            }
        } catch {
            recorder.cancel()
            sessionOutputMode = nil
            phase = .failed(error.localizedDescription)
            recordingHUD.hide()
        }
    }

    func finishRecording() {
        guard phase == .recording else { return }
        do {
            let wav = try recorder.stop()
            audioLevel = 0
            audioBands = .silent
            processingGeneration += 1
            let mode = settings.streamingMode
            let outputMode = sessionOutputMode
            let llmEnabled = settings.llmFeaturesAvailable
            let structured: Bool
            let prompt: Bool
            let smart: Bool
            switch outputMode {
            case .conversation:
                structured = false
                prompt = false
                smart = false
            case .english:
                structured = false
                prompt = false
                smart = false
            case .structured:
                structured = llmEnabled
                prompt = false
                smart = false
            case .prompt:
                structured = false
                prompt = llmEnabled
                smart = false
            case .smartRoute:
                structured = false
                prompt = false
                smart = llmEnabled
            case .none:
                structured = llmEnabled && settings.structuredOutputEnabled
                prompt = llmEnabled && settings.promptOptimizeEnabled
                smart = false
            }
            let streamingMode = settings.asrBackend == .api ? mode : .batch
            let snapshot = ProcessingSnapshot(
                wav: wav,
                transcript: nil,
                generation: processingGeneration,
                configuration: settings.configuration,
                targetLanguage: outputMode == .english
                    ? TargetLanguage.resolve(id: "en")
                    : settings.effectiveTargetLanguage,
                promptOptimizeEnabled: prompt,
                structuredOutputEnabled: structured,
                structuredEmojiEnabled: settings.structuredEmojiEnabled,
                structureIntensity: settings.structureIntensity,
                smartRouteEnabled: smart,
                translationConfiguration: settings.translationConfiguration,
                promptOptimizeConfiguration: settings.promptOptimizeConfiguration,
                smartRouteConfiguration: settings.smartRouteConfiguration,
                chatEndpoint: settings.llmEndpoint,
                languageModel: settings.translationModel,
                apiKey: settings.llmApiKey,
                streamingMode: streamingMode,
                outputMode: outputMode
            )
            transcriptionTask?.cancel()
            transcriptionTask = Task {
                defer { transcriptionTask = nil }
                await processRecordingSnapshot(snapshot)
            }
        } catch {
            streamingSession?.cancel()
            streamingSession = nil
            sessionOutputMode = nil
            stageTiming.finishSession(outcome: .failed, message: error.localizedDescription)
            phase = .failed(error.localizedDescription)
            recordingHUD.hide()
        }
    }

    private func processRecordingSnapshot(_ snapshot: ProcessingSnapshot) async {
        // Expired audio snapshots are discarded immediately.
        guard snapshot.generation == processingGeneration else { return }
        do {
            let transcript: String
            switch snapshot.streamingMode {
            case .duplexStreaming:
                stageTiming.enter(.finalizing)
                phase = .finalizing
                if let session = streamingSession {
                    transcript = try await session.finish()
                    streamingSession = nil
                } else if let wav = snapshot.wav {
                    // Session failed to open — fall back to batch on the captured WAV.
                    transcript = try await client.transcribe(
                        wav: wav,
                        configuration: snapshot.configuration,
                        onUsage: usageRecorder(stage: .transcription, model: snapshot.configuration.model)
                    )
                } else {
                    throw TranscriptionError.invalidResponse
                }
                publishFinalTranscript(transcript)

            case .sseResult:
                // Live captions already ran during recording; finalize on full WAV (+ SSE if available).
                streamingSession?.cancel()
                streamingSession = nil
                stageTiming.enter(.transcribing)
                phase = .transcribing
                guard let wav = snapshot.wav else { throw TranscriptionError.invalidResponse }
                transcript = try await client.transcribe(
                    wav: wav,
                    configuration: snapshot.configuration,
                    streamResults: true,
                    onEvent: { [weak self] event in
                        Task { @MainActor in
                            self?.handleTranscriptionEvent(event, generation: snapshot.generation)
                        }
                    },
                    onUsage: usageRecorder(stage: .transcription, model: snapshot.configuration.model)
                )
                publishFinalTranscript(transcript)

            case .batch:
                streamingSession?.cancel()
                streamingSession = nil
                stageTiming.enter(.transcribing)
                phase = .transcribing
                guard let wav = snapshot.wav else { throw TranscriptionError.invalidResponse }
                transcript = try await client.transcribe(
                    wav: wav,
                    configuration: snapshot.configuration,
                    onUsage: usageRecorder(stage: .transcription, model: snapshot.configuration.model)
                )
                publishFinalTranscript(transcript)
            }

            try Task.checkCancellation()
            guard snapshot.generation == processingGeneration else { return }

            // Pipeline: ASR → smart route | (optional structure) → (prompt optimize XOR translate)
            var working = transcript
            var output = working

            if snapshot.smartRouteEnabled {
                stageTiming.enter(.optimizing, detail: "智能路由")
                phase = .routing
                output = try await translator.translate(
                    text: transcript,
                    configuration: snapshot.smartRouteConfiguration,
                    onUsage: usageRecorder(
                        stage: .promptOptimization,
                        model: snapshot.smartRouteConfiguration.model
                    )
                )
                try Task.checkCancellation()
                guard snapshot.generation == processingGeneration else { return }
            } else {
            // Hotkey modes set structured/prompt flags on the snapshot; when both settings
            // toggles are on without a hotkey, skip structure while compiling (IR owns cleanup).
            let runStructure = snapshot.structuredOutputEnabled
                && !snapshot.promptOptimizeEnabled
            if runStructure {
                stageTiming.enter(.structuring)
                phase = .structuring
                let formatConfig = SemanticFormatterConfiguration(
                    endpoint: snapshot.chatEndpoint,
                    model: snapshot.languageModel,
                    apiKey: snapshot.apiKey,
                    mode: SemanticFormatter.resolveMode(
                        for: transcript,
                        intensity: snapshot.structureIntensity
                    ),
                    customSystemPrompt: snapshot.translationConfiguration.customSystemPrompt,
                    outputLanguageDirective: snapshot.targetLanguage.translates
                        ? snapshot.targetLanguage.outputLanguageDirective
                        : nil,
                    useEmoji: snapshot.structuredEmojiEnabled
                )
                working = try await formatter.format(
                    text: transcript,
                    configuration: formatConfig,
                    onUsage: usageRecorder(stage: .structuring, model: formatConfig.model)
                )
                try Task.checkCancellation()
                guard snapshot.generation == processingGeneration else { return }
            }

            output = working
            if snapshot.promptOptimizeEnabled {
                stageTiming.enter(.optimizing, detail: snapshot.promptOptimizeConfiguration.promptTarget.label)
                phase = .optimizing
                output = try await translator.translate(
                    text: working,
                    configuration: snapshot.promptOptimizeConfiguration,
                    onUsage: usageRecorder(
                        stage: .promptOptimization,
                        model: snapshot.promptOptimizeConfiguration.model
                    )
                )
                try Task.checkCancellation()
                guard snapshot.generation == processingGeneration else { return }
            } else if snapshot.targetLanguage.translates {
                stageTiming.enter(.translating)
                phase = .translating
                let baseTranslationConfig = snapshot.translationConfiguration
                let activeTranslationConfig = TranslationConfiguration(
                    endpoint: baseTranslationConfig.endpoint,
                    model: baseTranslationConfig.model,
                    targetLanguage: snapshot.targetLanguage.promptName,
                    styleHint: snapshot.targetLanguage.styleHint,
                    customSystemPrompt: baseTranslationConfig.customSystemPrompt,
                    apiKey: baseTranslationConfig.apiKey,
                    task: .translate,
                    promptTarget: baseTranslationConfig.promptTarget
                )
                var translation = try await translator.translate(
                    text: working,
                    configuration: activeTranslationConfig,
                    onUsage: usageRecorder(
                        stage: .translation, model: activeTranslationConfig.model
                    )
                )
                // If the model ignored the target language, force one stricter retry.
                if !snapshot.targetLanguage.outputLooksCompatible(translation) {
                    var retryConfig = activeTranslationConfig
                    // Strengthen directive in configuration only — never prepend meta tags to user text.
                    retryConfig = TranslationConfiguration(
                        endpoint: activeTranslationConfig.endpoint,
                        model: activeTranslationConfig.model,
                        targetLanguage: activeTranslationConfig.targetLanguage,
                        styleHint: """
                        \(activeTranslationConfig.styleHint)

                        CRITICAL: Write the entire translation in \(snapshot.targetLanguage.promptName) only.
                        Do not mention the required language in the output body.
                        """,
                        customSystemPrompt: activeTranslationConfig.customSystemPrompt,
                        apiKey: activeTranslationConfig.apiKey,
                        task: activeTranslationConfig.task,
                        promptTarget: activeTranslationConfig.promptTarget
                    )
                    translation = try await translator.translate(
                        text: working,
                        configuration: retryConfig,
                        onUsage: usageRecorder(stage: .translation, model: retryConfig.model)
                    )
                }
                if !snapshot.targetLanguage.outputLooksCompatible(translation) {
                    throw TranslationError.invalidResponse
                }
                try Task.checkCancellation()
                guard snapshot.generation == processingGeneration else { return }
                output = snapshot.targetLanguage.formatOutput(
                    transcript: working,
                    translation: translation
                )
            }
            } // end of non-smartRoute else block

            guard snapshot.generation == processingGeneration else { return }
            lastTranscript = output
            // Always stage clipboard so user can paste even if AX/Cmd+V insertion fails.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(output, forType: .string)
            do {
                stageTiming.enter(.paste)
                _ = try await PasteService.insert(output, into: inputTargetPID)
                stageTiming.finishSession(outcome: .success)
                phase = .success(output)
                NSSound(named: "Pop")?.play()
                try? await Task.sleep(for: .milliseconds(450))
            } catch {
                stageTiming.finishSession(
                    outcome: .failed,
                    message: "处理成功，但无法写入当前输入框"
                )
                let detail = error.localizedDescription
                phase = .failed("处理成功，但无法写入：\(detail)内容已复制，请手动粘贴。")
                try? await Task.sleep(for: .milliseconds(650))
            }
            recordingHUD.hide()
            resultBanner.show(text: output)
            sessionOutputMode = nil
        } catch {
            guard snapshot.generation == processingGeneration else { return }
            streamingSession?.cancel()
            streamingSession = nil
            let cancelled = error is CancellationError
            stageTiming.finishSession(
                outcome: cancelled ? .cancelled : .failed,
                message: cancelled ? "已取消" : error.localizedDescription
            )
            phase = .failed(cancelled ? "已取消。" : error.localizedDescription)
            try? await Task.sleep(for: .milliseconds(400))
            recordingHUD.hide()
            sessionOutputMode = nil
        }
    }

    private func usageRecorder(
        stage: UsageStage,
        model: String
    ) -> @Sendable (TokenUsage) -> Void {
        { [weak self] usage in
            Task { @MainActor in
                self?.tokenUsage.record(usage, stage: stage, model: model)
            }
        }
    }

    private func handleTranscriptionEvent(_ event: StreamingASREvent, generation: Int) {
        guard generation == processingGeneration else { return }
        switch event {
        case let .partial(text):
            stageTiming.markFirstPartial()
            publishThrottledPartial(stable: stableTranscript, unstable: text)
        case let .stable(text):
            stageTiming.markFirstPartial()
            stableTranscript = text
            publishThrottledPartial(stable: text, unstable: "")
        case let .final(text):
            publishFinalTranscript(text)
        case .usage, .error, .done:
            break
        }
    }

    private func publishAccumulator(_ accumulator: TranscriptAccumulator) {
        let display = accumulator.displayText
        let now = Date()
        // First glyph always publishes; afterwards ~20 Hz — never wait for big jumps.
        if !partialTranscript.isEmpty,
           now.timeIntervalSince(lastPartialPublishAt) < partialPublishInterval,
           display == partialTranscript {
            return
        }
        lastPartialPublishAt = now
        stableTranscript = accumulator.stablePrefix
        partialTranscript = display
        if accumulator.isFinalized {
            stableTranscript = display
        }
    }

    private func publishThrottledPartial(stable: String, unstable: String) {
        var acc = TranscriptAccumulator()
        if !stable.isEmpty { acc.applyStable(stable) }
        acc.applyPartial(unstable)
        publishAccumulator(acc)
    }

    private func publishFinalTranscript(_ text: String) {
        stableTranscript = text
        partialTranscript = text
    }

    func testConnection() {
        let configuration = settings.configuration
        if configuration.backend == .integrated {
            connectionMessage = "正在检查本地 ASR…"
            capabilityMessage = "本地原生 ASR：首次使用可能需要下载或加载模型。"
            Task {
                do {
                    try await client.checkServer(configuration: configuration)
                    connectionMessage = "本地 ASR 已就绪"
                } catch {
                    connectionMessage = "本地 ASR 检查失败：\(error.localizedDescription)"
                }
                let caps = await OMLXCapabilityProbe.probe(configuration: configuration)
                lastCapabilities = caps
                capabilityMessage = caps.summary
            }
            return
        }

        connectionMessage = "正在连接 ASR API…"
        capabilityMessage = "正在探测 API Streaming 能力…"
        Task {
            do {
                try await client.checkServer(configuration: configuration)
                connectionMessage = "ASR 连接成功"
            } catch {
                connectionMessage = "ASR 连接失败：\(error.localizedDescription)"
            }
            let caps = await OMLXCapabilityProbe.probe(configuration: configuration)
            lastCapabilities = caps
            capabilityMessage = caps.summary
        }
    }

    func prepareLocalASRModel() {
        let configuration = settings.configuration
        guard configuration.backend == .integrated else {
            connectionMessage = "API 模式不需要下载本地 ASR 模型"
            return
        }
        let guidance = NativeASRClient.downloadGuidance(configuration: configuration)
        connectionMessage = "正在准备本地 ASR 模型…"
        capabilityMessage = localASRPreparationMessage(configuration: configuration, guidance: guidance)
        Task {
            do {
                let result = try await NativeASRClient.shared.prepareRuntime(
                    configuration: configuration,
                    onProgress: { [weak self] message in
                        Task { @MainActor in
                            self?.capabilityMessage = message
                        }
                    }
                )
                if let path = result.modelPath,
                   configuration.integratedEngine == .qwen3MLX {
                    settings.integratedASRModelPath = path
                }
                connectionMessage = result.message
                let caps = await OMLXCapabilityProbe.probe(configuration: settings.configuration)
                lastCapabilities = caps
                capabilityMessage = caps.summary
            } catch {
                connectionMessage = "准备本地 ASR 失败：\(error.localizedDescription)"
                capabilityMessage = localASRFailureHelp(error: error, guidance: guidance)
            }
        }
    }

    private func localASRPreparationMessage(
        configuration: TranscriptionConfiguration,
        guidance: NativeASRDownloadGuidance
    ) -> String {
        var lines = [
            localASRModelSummary(configuration),
            guidance.detail,
            "手动下载命令：\(guidance.manualCommand)"
        ]
        if let hf = hfCLIPath() {
            lines.append("已检测到 hf CLI：\(hf)")
        } else {
            lines.append("未检测到 hf CLI；内置下载器仍会尝试下载。需要手动处理时，请先安装：python3 -m pip install --user -U huggingface_hub hf-xet")
        }
        return lines.joined(separator: "\n")
    }

    private func localASRModelSummary(_ configuration: TranscriptionConfiguration) -> String {
        switch configuration.integratedEngine {
        case .qwen3MLX:
            let path = configuration.integratedModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty
                ? "当前本地 ASR：Qwen3-ASR · \(configuration.qwenModelRepo)"
                : "当前本地 ASR：Qwen3-ASR · \(configuration.qwenModelRepo) · \(path)"
        case .whisperMLX:
            let model = AppSettings.normalizeWhisperKitModel(configuration.whisperKitModel)
            return "当前本地 ASR：WhisperKit · \(model.isEmpty ? "tiny" : model)"
        }
    }

    private func localASRFailureHelp(error: Error, guidance: NativeASRDownloadGuidance) -> String {
        let text = error.localizedDescription.lowercased()
        var lines: [String] = []
        if text.contains("401") || text.contains("403") || text.contains("unauthorized") || text.contains("forbidden") || text.contains("gated") {
            lines.append("看起来需要 Hugging Face 授权。请在终端执行：hf auth login")
        }
        if text.contains("model load failed") || text.contains("failed to load") || text.contains("runtime init failed") {
            lines.append("模型文件存在但运行时加载失败。请先点「准备模型」修复缓存；如果仍失败，切换到 WhisperKit tiny 或重新下载 Qwen3-ASR 6bit。")
        }
        lines.append("也可以手动下载后再回到本页检查。")
        lines.append("命令：\(guidance.manualCommand)")
        if hfCLIPath() == nil {
            lines.append("如果提示找不到 hf，请先执行：python3 -m pip install --user -U huggingface_hub hf-xet")
        }
        return lines.joined(separator: "\n")
    }

    private func hfCLIPath() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/Library/Python/3.9/bin/hf",
            "\(NSHomeDirectory())/.local/bin/hf",
            "/opt/homebrew/bin/hf",
            "/usr/local/bin/hf"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Probe translation / Prompt LLM endpoint and confirm the configured model is listed.
    func testLanguageModelConnection() {
        guard settings.llmBackend == .api else {
            connectionMessage = "翻译/整理/Prompt 编译已关闭"
            return
        }
        guard settings.llmFeaturesAvailable else {
            connectionMessage = "请先配置 LLM API 地址和模型名"
            return
        }
        let configuration = settings.translationConfiguration
        connectionMessage = "正在连接翻译模型…"
        Task {
            do {
                let detail = try await translator.checkServer(configuration: configuration)
                connectionMessage = detail
            } catch {
                connectionMessage = "翻译连接失败：\(error.localizedDescription)"
            }
        }
    }

    /// Menu-bar probe: ASR + translation model in one pass.
    func testConnections() {
        let asrConfig = settings.configuration
        let llmConfig = settings.translationConfiguration
        connectionMessage = "正在测试连接…"
        capabilityMessage = asrConfig.backend == .integrated
            ? "正在检查本地原生 ASR…"
            : "正在探测 API Streaming 能力…"
        Task {
            var parts: [String] = []
            do {
                try await client.checkServer(configuration: asrConfig)
                parts.append(asrConfig.backend == .integrated ? "本地 ASR 正常" : "ASR API 正常")
            } catch {
                parts.append("ASR 失败：\(error.localizedDescription)")
            }
            do {
                if settings.llmFeaturesAvailable {
                    let detail = try await translator.checkServer(configuration: llmConfig)
                    parts.append(detail)
                } else {
                    parts.append("LLM 后处理未启用")
                }
            } catch {
                parts.append("翻译失败：\(error.localizedDescription)")
            }
            connectionMessage = parts.joined(separator: " · ")
            let caps = await OMLXCapabilityProbe.probe(configuration: asrConfig)
            lastCapabilities = caps
            capabilityMessage = caps.summary
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        writeTranscriptToPasteboard(lastTranscript)
    }

    /// Copy whatever the HUD is currently showing (live partial text during
    /// recording / 收敛 / 转写 / 整理). Falls back to the last finished transcript.
    func copyPartialTranscript() {
        let live = partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let finished = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = live.isEmpty ? finished : live
        guard !text.isEmpty else { return }
        writeTranscriptToPasteboard(text)
    }

    private func writeTranscriptToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        transcriptCopied = true
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            transcriptCopied = false
        }
    }

    /// Re-run semantic formatter on the latest successful text (no new ASR).
    func reformatLastTranscript() {
        let source = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        switch phase {
        case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing:
            return
        default:
            break
        }
        guard settings.llmFeaturesAvailable else {
            connectionMessage = "请先在翻译与整理中启用并配置 LLM API 模式"
            return
        }

        processingGeneration += 1
        let generation = processingGeneration
        transcriptionTask?.cancel()
        transcriptionTask = Task {
            defer { transcriptionTask = nil }
            resultBanner.hide()
            stageTiming.beginSession(promptTarget: nil)
            stageTiming.enter(.structuring)
            phase = .structuring
            recordingHUD.show()
            do {
                let formatConfig = settings.semanticFormatterConfiguration(for: source)
                let output = try await formatter.format(text: source, configuration: formatConfig)
                try Task.checkCancellation()
                guard generation == processingGeneration else { return }

                lastTranscript = output
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(output, forType: .string)
                do {
                    stageTiming.enter(.paste)
                    _ = try await PasteService.insert(output, into: inputTargetPID)
                    stageTiming.finishSession(outcome: .success)
                    phase = .success(output)
                    NSSound(named: "Pop")?.play()
                    try? await Task.sleep(for: .milliseconds(450))
                } catch {
                    stageTiming.finishSession(
                        outcome: .failed,
                        message: "整理成功，但无法写入当前输入框"
                    )
                    let detail = error.localizedDescription
                    phase = .failed("整理成功，但无法写入：\(detail)内容已复制，请手动粘贴。")
                    try? await Task.sleep(for: .milliseconds(650))
                }
                recordingHUD.hide()
                resultBanner.show(text: output)
            } catch {
                guard generation == processingGeneration else { return }
                let cancelled = error is CancellationError
                stageTiming.finishSession(
                    outcome: cancelled ? .cancelled : .failed,
                    message: cancelled ? "已取消" : error.localizedDescription
                )
                phase = .failed(cancelled ? "已取消。" : error.localizedDescription)
                try? await Task.sleep(for: .milliseconds(400))
                recordingHUD.hide()
            }
        }
    }

    /// Abort recording or any in-flight pipeline stage without producing output.
    func cancelActiveSession() {
        if settings.effectiveVoicePipelineEnabled,
           voicePipeline.isListening
            || isStartingVoicePipeline
            || {
                if case .failed = voicePipeline.state { return true }
                return false
            }() {
            stopVoicePipeline()
            return
        }
        switch phase {
        case .recording:
            processingGeneration += 1
            transcriptionTask?.cancel()
            transcriptionTask = nil
            streamingSession?.cancel()
            streamingSession = nil
            recorder.cancel()
            audioLevel = 0
            audioBands = .silent
            partialTranscript = ""
            stableTranscript = ""
            sessionOutputMode = nil
            if stageTiming.hasActiveSession {
                stageTiming.finishSession(outcome: .cancelled, message: "已取消")
            }
            phase = .idle
            recordingHUD.hide()
        case .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing:
            cancelTranscription()
        default:
            break
        }
    }

    func cancelTranscription() {
        guard phase == .finalizing
            || phase == .transcribing
            || phase == .structuring
            || phase == .translating
            || phase == .optimizing
            || phase == .routing else { return }
        processingGeneration += 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        streamingSession?.cancel()
        streamingSession = nil
        stageTiming.finishSession(outcome: .cancelled, message: "已取消")
        phase = .failed("已取消。")
        recordingHUD.hide()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }

            settings.launchAtLogin = enabled
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLoginEnabled {
                launchAtLoginMessage = "需要在系统设置的登录项中允许 Vibe Voice OSS。"
            } else {
                launchAtLoginMessage = enabled ? "已启用" : "已关闭"
            }
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            launchAtLoginMessage = "设置失败：\(error.localizedDescription)"
        }
    }

    func requestPermissions() {
        let trusted = PasteService.requestAccessibilityIfNeeded(prompt: true)
        capabilityMessage = trusted
            ? "辅助使用权限已授权，可以自动写入当前输入框。"
            : "已打开辅助使用授权提示；授权前会只复制到剪贴板，不会反复弹窗。"
        Task { @MainActor in
            guard !isStartingRecording, phase != .recording else { return }
            isStartingRecording = true
            defer { isStartingRecording = false }
            do {
                try await recorder.start(deviceUID: settings.inputDeviceUID)
                recorder.cancel()
            } catch {
                recorder.cancel()
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
