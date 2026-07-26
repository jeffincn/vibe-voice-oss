import SwiftUI

struct MobileHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bridgeState = VoiceBridgeState.idle
    @State private var bridgeWatcher: VoiceBridgeWatcher?
    @State private var rimeStatus = "尚未准备"
    @State private var isPreparingRime = false
    @StateObject private var voiceController = MobileVoiceController()
    private let bridge = VoiceBridgeStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    setupCard
                    bridgeCard
                    modelCard
                    privacyCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Vibe Voice")
            .task {
                prepareRime()
                startObservingBridge()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    // The keyboard cannot ask for anything while we are not
                    // frontmost, so stop listening instead of waking up to poll.
                    bridgeWatcher = nil
                    voiceController.handleBackgroundTransition()
                case .active:
                    startObservingBridge()
                default:
                    break
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iOS 0.7.0 Alpha", systemImage: "waveform.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.tint)
                .accessibilityIdentifier("home.hero")
            Text("Rime 全拼与语音输入的移动端工作区。键盘目前提供字母、候选与语音键，数字、符号与 Shift 仍在开发中。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("启用键盘", systemImage: "keyboard")
                .font(.headline)
            Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → Vibe Voice。语音桥接需要“允许完全访问”；基础中英文输入将保持离线可用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var bridgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("语音桥接", systemImage: "mic.fill")
                    .font(.headline)
                Spacer()
                Text(bridgeState.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(voiceController.phase.label)
                .font(.subheadline.weight(.medium))
            Picker("输出", selection: Binding(
                get: { voiceController.outputMode },
                set: { voiceController.selectOutputMode($0) }
            )) {
                ForEach(VoiceOutputMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("voice.outputMode")
            ProgressView(value: Double(voiceController.level))
                .tint(voiceController.phase == .recording ? .red : .accentColor)
            HStack {
                Button(voiceController.phase == .recording ? "停止并转写" : "开始录音") {
                    if voiceController.phase == .recording {
                        voiceController.stopAndTranscribe()
                    } else {
                        voiceController.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("voice.record")
                Button("重置") {
                    voiceController.reset()
                    refreshBridgeState()
                }
                .buttonStyle(.bordered)
            }
            if !voiceController.transcript.isEmpty {
                Text(voiceController.transcript)
                    .textSelection(.enabled)
            }
            Text("iOS 不允许第三方键盘扩展直接使用麦克风。键盘发起请求后，请切到此页录音；转写完成再切回原输入框，结果会自动插入。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("“翻译”使用 Whisper 的语音转英文能力；“整理”在设备上清理空白并补齐句末标点，不上传文本。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本地模型", systemImage: "cpu")
                .font(.headline)
            LabeledContent("WhisperKit tiny", value: voiceController.modelStatus)
            Button("下载并预热语音模型") {
                voiceController.prepareModel()
            }
            .buttonStyle(.bordered)
            .disabled(voiceController.phase == .preparingModel || voiceController.phase == .recording)
            .accessibilityIdentifier("model.prepare")
            Text("应用进入后台且没有录音或转写任务时，会自动卸载模型释放内存；下载文件仍保留在设备上。")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Qwen3-ASR", value: "实验性")
            LabeledContent("Rime 全拼", value: rimeStatus)
            Button(isPreparingRime ? "正在部署词库…" : "重新准备 Rime") {
                prepareRime(fullCheck: true)
            }
            .buttonStyle(.bordered)
            .disabled(isPreparingRime)
            Text("首次启用键盘前，请至少打开一次主应用。词库部署完成后，键盘扩展直接复用共享数据，不在输入时执行维护任务。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("隐私与数据", systemImage: "lock.shield")
                .font(.headline)
            Text("语音转写只在本机进行，不上传音频或文字。转写结果写入键盘共享容器，插入后立即删除；键盘的拼音学习记录保存在共享容器内，仅本机可读。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("清除共享数据与拼音学习记录", role: .destructive) {
                clearSharedData()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("privacy.clear")
            Text("清除后键盘会重新从零学习，已部署的词库不受影响。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func clearSharedData() {
        voiceController.reset()
        bridge.reset()
        RimeEngineFactory.clearLearningData()
        refreshBridgeState()
        rimeStatus = "已清除学习记录"
    }

    private func startObservingBridge() {
        refreshBridgeState()
        guard bridgeWatcher == nil else { return }
        bridgeWatcher = VoiceBridgeWatcher {
            refreshBridgeState()
        }
    }

    private func refreshBridgeState() {
        bridgeState = bridge.load()
        voiceController.synchronize(with: bridgeState)
    }

    /// - Parameter fullCheck: re-verifies every dictionary. Reserved for the
    ///   repair button; a launch only deploys what actually changed.
    private func prepareRime(fullCheck: Bool = false) {
        guard !isPreparingRime else { return }
        isPreparingRime = true
        rimeStatus = "准备中"
        Task {
            let message = await Task.detached(priority: .userInitiated) {
                do {
                    _ = try RimeEngineFactory.prepareForMainApp(fullCheck: fullCheck)
                    return "已就绪"
                } catch {
                    return "失败：\(error.localizedDescription)"
                }
            }.value
            rimeStatus = message
            isPreparingRime = false
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
