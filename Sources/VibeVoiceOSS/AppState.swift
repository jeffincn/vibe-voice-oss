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
        case success(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle: "按快捷键开始，再按一次结束"
            case .recording: "正在录音…再按一次结束"
            case .finalizing: "正在收敛识别…"
            case .transcribing: "正在转写…"
            case .structuring: "正在整理内容…"
            case .translating: "正在翻译…"
            case .optimizing: "正在编译 Prompt…"
            case let .success(text): text
            case let .failed(message): message
            }
        }

        func label(hotKey: RecordingHotKey) -> String {
            switch self {
            case .idle: "按 \(hotKey.label) 开始，再按一次结束"
            case .recording: "正在录音…按 \(hotKey.label) 结束"
            default: label
            }
        }

        func label(mode: RecordingOutputMode?) -> String {
            switch self {
            case .idle:
                return RecordingOutputMode.shortcutLegend
            case .recording:
                if let mode {
                    return "正在录音（\(mode.label)）…按 \(mode.chordLabel) 结束"
                }
                return "正在录音…再按一次结束"
            default:
                return label
            }
        }

        var symbol: String {
            switch self {
            case .idle, .success: "waveform"
            case .recording: "record.circle.fill"
            case .finalizing, .transcribing, .structuring, .translating, .optimizing: "ellipsis.circle"
            case .failed: "exclamationmark.triangle"
            }
        }

        var isBusy: Bool {
            switch self {
            case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing: true
            default: false
            }
        }

        /// High-level HUD caption (animation window).
        var hudPrimary: String {
            switch self {
            case .recording: "录音中"
            case .finalizing: "收敛中"
            case .transcribing: "转写中"
            case .structuring: "整理中"
            case .translating: "翻译中"
            case .optimizing: "输出 Prompt"
            case .success: "完成"
            case .failed: "失败"
            case .idle: ""
            }
        }

        /// Whether this phase can show a nested engine / target sub-status.
        var showsHUDSecondary: Bool {
            if case .optimizing = self { return true }
            return false
        }

        var drivesLiveAudioVisual: Bool {
            self == .recording
        }
    }

    /// Nested HUD line for Prompt compile — e.g. Codex / Claude Code.
    var hudSecondary: String? {
        guard phase.showsHUDSecondary else { return nil }
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

    var inputDeviceName: String { recorder.deviceName(for: settings.inputDeviceUID) }

    private let recorder = AudioRecorder()
    private let client = TranscriptionClient()
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

    var phaseLabel: String { phase.label(mode: sessionOutputMode) }

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
        let translationConfiguration: TranslationConfiguration
        let promptOptimizeConfiguration: TranslationConfiguration
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
                    if self.phase == .recording {
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
        }
    }

    /// Kept for Settings UI refresh after unrelated preference changes.
    func applyRecordingHotKeyFromSettings() {
        hotKey.registerAll()
        objectWillChange.send()
    }

    func beginRecording(outputMode: RecordingOutputMode? = nil) async {
        guard !isStartingRecording else { return }
        if case .recording = phase { return }

        isStartingRecording = true
        defer { isStartingRecording = false }

        switch phase {
        case .finalizing, .transcribing, .structuring, .translating, .optimizing:
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
                promptLabel = settings.promptTarget.label
            case .none:
                promptLabel = settings.promptOptimizeEnabled ? settings.promptTarget.label : nil
            case .conversation, .structured:
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
                }
            )
            streamingSession = session
            let wsURL = settings.streamingMode == .duplexStreaming
                ? URL(string: settings.streamingWSURL)
                : nil
            await session.open(
                configuration: settings.configuration,
                streamingWSURL: wsURL
            )
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
            let structured: Bool
            let prompt: Bool
            switch outputMode {
            case .conversation:
                structured = false
                prompt = false
            case .structured:
                structured = true
                prompt = false
            case .prompt:
                structured = false
                prompt = true
            case .none:
                structured = settings.structuredOutputEnabled
                prompt = settings.promptOptimizeEnabled
            }
            let snapshot = ProcessingSnapshot(
                wav: wav,
                transcript: nil,
                generation: processingGeneration,
                configuration: settings.configuration,
                targetLanguage: settings.targetLanguage,
                promptOptimizeEnabled: prompt,
                structuredOutputEnabled: structured,
                structuredEmojiEnabled: settings.structuredEmojiEnabled,
                structureIntensity: settings.structureIntensity,
                translationConfiguration: settings.translationConfiguration,
                promptOptimizeConfiguration: settings.promptOptimizeConfiguration,
                chatEndpoint: settings.llmEndpoint,
                languageModel: settings.translationModel,
                apiKey: settings.llmApiKey,
                streamingMode: mode,
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
                    transcript = try await client.transcribe(wav: wav, configuration: snapshot.configuration)
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
                    }
                )
                publishFinalTranscript(transcript)

            case .batch:
                streamingSession?.cancel()
                streamingSession = nil
                stageTiming.enter(.transcribing)
                phase = .transcribing
                guard let wav = snapshot.wav else { throw TranscriptionError.invalidResponse }
                transcript = try await client.transcribe(wav: wav, configuration: snapshot.configuration)
                publishFinalTranscript(transcript)
            }

            try Task.checkCancellation()
            guard snapshot.generation == processingGeneration else { return }

            // Pipeline: ASR → (optional structure) → (prompt optimize XOR translate)
            // Hotkey modes set structured/prompt flags on the snapshot; when both settings
            // toggles are on without a hotkey, skip structure while compiling (IR owns cleanup).
            var working = transcript
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
                    outputLanguageDirective: snapshot.targetLanguage.translates
                        ? snapshot.targetLanguage.outputLanguageDirective
                        : nil,
                    useEmoji: snapshot.structuredEmojiEnabled
                )
                working = try await formatter.format(text: transcript, configuration: formatConfig)
                try Task.checkCancellation()
                guard snapshot.generation == processingGeneration else { return }
            }

            var output = working
            if snapshot.promptOptimizeEnabled {
                stageTiming.enter(.optimizing, detail: snapshot.promptOptimizeConfiguration.promptTarget.label)
                phase = .optimizing
                output = try await translator.translate(
                    text: working,
                    configuration: snapshot.promptOptimizeConfiguration
                )
                try Task.checkCancellation()
                guard snapshot.generation == processingGeneration else { return }
            } else if snapshot.targetLanguage.translates {
                stageTiming.enter(.translating)
                phase = .translating
                var translation = try await translator.translate(
                    text: working,
                    configuration: snapshot.translationConfiguration
                )
                // If the model ignored the target language, force one stricter retry.
                if !snapshot.targetLanguage.outputLooksCompatible(translation) {
                    translation = try await translator.translate(
                        text: """
                        [REQUIRED OUTPUT LANGUAGE: \(snapshot.targetLanguage.promptName)]
                        \(working)
                        """,
                        configuration: snapshot.translationConfiguration
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
                // Keep HUD visible briefly so "完成" status is readable.
                try? await Task.sleep(for: .milliseconds(450))
            } catch {
                stageTiming.finishSession(
                    outcome: .failed,
                    message: "处理成功，但无法写入当前输入框"
                )
                phase = .failed("处理成功，但无法写入当前输入框。内容已复制，请手动粘贴。")
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
        case .error, .done:
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
        connectionMessage = "正在连接 ASR…"
        capabilityMessage = "正在探测 Streaming 能力…"
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

    /// Probe translation / Prompt LLM endpoint and confirm the configured model is listed.
    func testLanguageModelConnection() {
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
        capabilityMessage = "正在探测 Streaming 能力…"
        Task {
            var parts: [String] = []
            do {
                try await client.checkServer(configuration: asrConfig)
                parts.append("ASR 正常")
            } catch {
                parts.append("ASR 失败：\(error.localizedDescription)")
            }
            do {
                let detail = try await translator.checkServer(configuration: llmConfig)
                parts.append(detail)
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
        transcriptCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            transcriptCopied = false
        }
    }

    /// Re-run semantic formatter on the latest successful text (no new ASR).
    func reformatLastTranscript() {
        let source = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }
        switch phase {
        case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing:
            return
        default:
            break
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
                    phase = .failed("整理成功，但无法写入当前输入框。内容已复制，请手动粘贴。")
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
        case .finalizing, .transcribing, .structuring, .translating, .optimizing:
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
            || phase == .optimizing else { return }
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
        _ = PasteService.requestAccessibilityIfNeeded()
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
