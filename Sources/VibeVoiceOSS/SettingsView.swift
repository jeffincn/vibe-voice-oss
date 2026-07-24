import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsForm(settings: appState.settings)
            .environmentObject(appState)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case recognition
    case audio
    case translation
    case prompt
    case shortcuts
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: L10n.t(.paneGeneral)
        case .recognition: L10n.t(.paneRecognition)
        case .audio: L10n.t(.paneAudio)
        case .translation: L10n.t(.paneTranslation)
        case .prompt: L10n.t(.panePrompt)
        case .shortcuts: L10n.t(.paneShortcuts)
        case .performance: L10n.t(.panePerformance)
        }
    }

    var symbol: String {
        switch self {
        case .general: "globe"
        case .recognition: "waveform"
        case .audio: "slider.horizontal.3"
        case .translation: "character.book.closed"
        case .prompt: "text.book.closed"
        case .shortcuts: "keyboard"
        case .performance: "stopwatch"
        }
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: AppSettings
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var pane: SettingsPane = .general
    @State private var inputDevices = AudioInputDevices.all()

    var body: some View {
        let _ = settings.uiLanguageID
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)

            detailPanel
                .padding(.trailing, 16)
                .padding(.vertical, 16)
        }
        .background(AppChrome.canvas)
        .frame(minWidth: 820, idealWidth: 860, minHeight: 560, idealHeight: 640)
        .onAppear { inputDevices = AudioInputDevices.all() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppChrome.ink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vibe Voice OSS")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppChrome.ink)
                    Text(AppVersion.fullLabel)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(AppChrome.muted)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { item in
                    sidebarRow(item)
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppChrome.canvas)
    }

    private func sidebarRow(_ item: SettingsPane) -> some View {
        let selected = pane == item
        return Button {
            pane = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? AppChrome.ink : AppChrome.sidebarIdle)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? AppChrome.sidebarActiveFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(pane.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppChrome.ink)
                Spacer(minLength: 12)
                detailHeaderAction
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()
                .overlay(AppChrome.hairline)
                .padding(.horizontal, 8)

            ScrollView {
                detailContent
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppChrome.panel)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppChrome.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailHeaderAction: some View {
        switch pane {
        case .performance:
            pillButton(L10n.t(.settingsOpenTiming)) {
                openWindow(id: "stage-timing-report")
                AppActivation.promoteForUserWindows()
            }
        case .recognition:
            pillButton(settings.asrBackend == .integrated ? L10n.t(.settingsCheckASR) : L10n.t(.settingsTestASR)) {
                appState.testConnection()
            }
        case .translation:
            pillButton(L10n.t(.settingsTestTranslation)) { appState.testLanguageModelConnection() }
        case .shortcuts:
            pillButton(L10n.t(.settingsCheckPermissions)) { appState.requestPermissions() }
        default:
            EmptyView()
        }
    }

    private func pillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule(style: .continuous).fill(AppChrome.ink))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch pane {
        case .general:
            generalPane
        case .performance:
            performanceSection
        case .recognition:
            recognitionSection
        case .audio:
            audioSection
        case .translation:
            translationSection
        case .prompt:
            promptSection
        case .shortcuts:
            shortcutsSection
        }
    }

    // MARK: - Sections (behavior preserved)

    @ViewBuilder
    private var performanceSection: some View {
        settingsStack {
            if let latest = appState.stageTiming.latestSession {
                settingsCard {
                    labeledRow(L10n.t(.latestTotal), "\(latest.formattedTotal) · \(latest.outcome.label)")
                    if !latest.stages.isEmpty {
                        ForEach(latest.stages.prefix(6)) { stage in
                            labeledRow(
                                stage.detail.map { "\(stage.stage.label) · \($0)" } ?? stage.stage.label,
                                StageTimingFormatter.formatMs(stage.durationMs)
                            )
                        }
                    }
                }
            } else {
                caption(L10n.t(.stageTimingEmptyCaption))
            }
        }
    }

    private var generalPane: some View {
        settingsCard {
            pickerRow(L10n.t(.uiLanguage)) {
                Picker("", selection: $settings.uiLanguageID) {
                    ForEach(AppUILanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            caption(L10n.t(.uiLanguageCaption))
        }
    }

    private var recognitionSection: some View {
        settingsStack {
            settingsCard {
                pickerRow(L10n.t(.settingsASRMode)) {
                    Picker("", selection: Binding(
                        get: { settings.asrBackend },
                        set: { settings.asrBackend = $0 }
                    )) {
                        ForEach(ASRBackend.allCases) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                caption(settings.asrBackend.caption)
                Toggle("Voice Pipeline（VAD 切段）", isOn: $settings.voicePipelineEnabled)
                    .toggleStyle(.switch)
                    .disabled(!settings.isVoicePipelineAvailable)
                if settings.isVoicePipelineAvailable {
                    caption("开启后按热键进入持续聆听：停顿自动切段识别并显示字幕；再按同一热键或点停止后，按当前输出规则（整理 / 翻译 / Prompt 优化 / 智能路由，与普通录音相同）处理后粘贴。会话中的字幕是原始识别，结束时才做后处理。")
                } else {
                    caption("Voice Pipeline 仅在「集成模式」下可用；当前为 API 模式，已强制关闭。")
                }
                if settings.asrBackend == .integrated {
                    pickerRow("本地引擎") {
                        Picker("", selection: Binding(
                            get: { settings.integratedASREngine },
                            set: { settings.integratedASREngine = $0 }
                        )) {
                            ForEach(IntegratedASREngine.allCases) { engine in
                                Text(engine.label).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    caption(settings.integratedASREngine.caption)
                    if settings.integratedASREngine == .qwen3MLX {
                        field("Qwen 模型 Repo", text: $settings.qwenModelRepo)
                        caption("默认 mlx-community/Qwen3-ASR-0.6B-6bit；也可改成 mlx-community/Qwen3-ASR-0.6B-4bit / 8bit。")
                        directoryField("Qwen 模型目录", text: $settings.integratedASRModelPath)
                        caption(settings.integratedASRModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "当前模型：Qwen3-ASR · \(settings.qwenModelRepo)"
                            : "当前模型：Qwen3-ASR · \(settings.qwenModelRepo) · \(settings.integratedASRModelPath)")
                        caption("点「准备模型」会自动下载并填写目录；手动目录需包含 config.json、model.safetensors 以及 tokenizer 文件。")
                    } else {
                        field("WhisperKit 模型", text: $settings.whisperKitModel)
                        caption("当前模型：WhisperKit · \(settings.whisperKitModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tiny" : settings.whisperKitModel)")
                        caption("例如 tiny 或 large-v3-v20240930_626MB；点「准备模型」会下载缺失文件并修复不完整缓存。")
                    }
                    field("HF 镜像端点（可选）", text: $settings.hfEndpoint)
                    caption("直连 huggingface.co 不稳定时可填镜像，例如 https://hf-mirror.com；留空使用官方源。")
                } else {
                    field("API 地址", text: $settings.endpoint)
                    secureField("API Key（未启用可留空）", text: $settings.apiKey)
                    field("模型名", text: $settings.model)
                }
                field(L10n.t(.recognitionLanguage), text: $settings.language)
                caption(L10n.t(.recognitionLanguageCaption))
            }

            if settings.asrBackend == .api {
                caption("模型名请与 oMLX / 远端已加载的 ASR 名称一致，可直接手输。")
                caption("录音时会像字幕一样实时显示识别文字（重叠窗伪流式）。下方模式只影响停录后的最终收敛方式。")

                settingsCard {
                    pickerRow("识别模式") {
                        Picker("", selection: Binding(
                            get: { settings.streamingMode },
                            set: { settings.streamingMode = $0 }
                        )) {
                            ForEach(StreamingMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    caption(settings.streamingMode.caption)
                    if settings.streamingMode == .duplexStreaming {
                        field(L10n.t(.settingsDuplexWS), text: $settings.streamingWSURL)
                        caption("连不上时自动降级为重叠窗伪流式（仍走本机转写接口）。")
                    }
                }
            } else {
                caption("集成模式停录后直接在本机转写；实时字幕和 WebSocket 仅在 API 模式下可用。")
            }

            HStack(spacing: 10) {
                if settings.asrBackend == .integrated {
                    if appState.isPreparingLocalASRModel {
                        secondaryPill("取消下载") { appState.cancelLocalASRModelPreparation() }
                    } else {
                        secondaryPill(L10n.t(.settingsPrepareModel)) { appState.prepareLocalASRModel() }
                    }
                }
                secondaryPill(settings.asrBackend == .integrated ? "检查本地 ASR" : "测试 ASR") {
                    appState.testConnection()
                }
                Spacer(minLength: 0)
            }

            if !appState.capabilityMessage.isEmpty {
                caption(appState.capabilityMessage)
            }
            if !appState.connectionMessage.isEmpty {
                Text(appState.connectionMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(connectionMessageColor)
            }
        }
    }

    @ViewBuilder
    private var audioSection: some View {
        settingsStack {
            settingsCard {
                pickerRow("转码配置") {
                    Picker("", selection: Binding(
                        get: { settings.transcodeProfile },
                        set: { settings.transcodeProfile = $0 }
                    )) {
                        ForEach(TranscodeProfile.allCases) { profile in
                            Text(profile.label).tag(profile)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                caption(settings.transcodeProfile.caption)
                labeledRow("采样率", "\(settings.transcodeProfile.sampleRate) Hz")
                labeledRow("声道", "\(settings.transcodeProfile.channels)")
                labeledRow(
                    "编码",
                    "\(settings.transcodeProfile.container) / \(settings.transcodeProfile.codec) · \(settings.transcodeProfile.bitDepth)-bit"
                )
                Toggle("自动增益 / 归一化", isOn: $settings.transcodeNormalize)
                    .toggleStyle(.switch)
                HStack {
                    Text("最大增益")
                        .foregroundStyle(AppChrome.ink)
                    Spacer()
                    Text("\(Int(settings.transcodeMaxGainDb)) dB")
                        .foregroundStyle(AppChrome.muted)
                        .monospacedDigit()
                }
                Slider(value: $settings.transcodeMaxGainDb, in: 0...24, step: 1)
            }
            caption(L10n.t(.localAudioSpecCaption))
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        settingsStack {
            settingsCard {
                pickerRow("LLM 后处理") {
                    Picker("", selection: Binding(
                        get: { settings.llmBackend },
                        set: { settings.llmBackend = $0 }
                    )) {
                        ForEach(LanguageModelBackend.allCases) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                caption(settings.llmBackend.caption)
                field("API 地址", text: $settings.llmEndpoint)
                    .disabled(settings.llmBackend != .api)
                secureField("API Key（未启用可留空）", text: $settings.llmApiKey)
                    .disabled(settings.llmBackend != .api)
                field("模型名", text: $settings.translationModel)
                    .disabled(settings.llmBackend != .api)
                VStack(alignment: .leading, spacing: 6) {
                    Text("自定义 System Prompt")
                        .font(.system(size: 12, weight: .medium))
                    TextEditor(text: $settings.llmSystemPrompt)
                        .font(.system(size: 13))
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(AppChrome.canvas, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(settings.llmBackend != .api)
                caption("翻译/整理/Prompt 编译时作为附加指令；⌘⇧G 智能路由时作为唯一系统指令。")
                pickerRow(L10n.t(.outputLanguage)) {
                    Picker("", selection: $settings.targetLanguageID) {
                        ForEach(TargetLanguage.all) { language in
                            Text(language.label).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .disabled(!settings.llmFeaturesAvailable)
            }

            if settings.llmBackend == .api {
                caption("模型名请填写 oMLX / 兼容服务端已加载的 chat 模型；可留空后按需填写。")
                caption("按模型名自动选择 Provider Profile：含 qwen → Qwen；含 nemotron → NVIDIA Nemotron；其余 → OpenAI 兼容。")
                caption("API Key 保存在 macOS 钥匙串；无稳定签名的临时构建会退回本机 UserDefaults。")
            } else {
                caption("关闭时只输出 ASR 原文，下面的翻译、整理和 Prompt 编译参数不会生效。")
            }

            settingsCard {
                Toggle("使用结构化输出", isOn: $settings.structuredOutputEnabled)
                    .toggleStyle(.switch)
                    .disabled(!settings.llmFeaturesAvailable)
                if settings.structuredOutputEnabled {
                    Toggle("使用 Emoji", isOn: $settings.structuredEmojiEnabled)
                        .toggleStyle(.switch)
                        .disabled(!settings.llmFeaturesAvailable)
                    pickerRow(L10n.t(.structureIntensity)) {
                        Picker("", selection: Binding(
                            get: { settings.structureIntensity },
                            set: { settings.structureIntensity = $0 }
                        )) {
                            ForEach(StructureIntensity.allCases) { intensity in
                                Text(intensity.label).tag(intensity)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .disabled(!settings.llmFeaturesAvailable)
                    caption(settings.structureIntensity.caption)
                    caption(settings.structuredEmojiEnabled
                        ? "分区标题会带修饰性 emoji（如 ✅ 📌）。"
                        : "默认不加 emoji，只用短段与中文小标题。")
                }
                Toggle("Prompt 优化", isOn: $settings.promptOptimizeEnabled)
                    .toggleStyle(.switch)
                    .disabled(!settings.llmFeaturesAvailable)
                if settings.promptOptimizeEnabled {
                    pickerRow(L10n.t(.targetAgent)) {
                        Picker("", selection: $settings.promptTargetID) {
                            ForEach(PromptTargetKind.allCases) { target in
                                Text(target.label).tag(target.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .disabled(!settings.llmFeaturesAvailable)
                    caption(settings.promptTarget.caption)
                }
            }
            caption("翻译 / 结构化 / Prompt 编译只在 LLM API 模式且模型配置完整时启用，可与 ASR 完全不同。")
            if !appState.connectionMessage.isEmpty {
                Text(appState.connectionMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(connectionMessageColor)
            }
        }
    }

    @ViewBuilder
    private var promptSection: some View {
        settingsStack {
            settingsCard {
                TextEditor(text: $settings.prompt)
                    .font(.system(size: 14))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
            }
            caption(L10n.t(.promptHintWordsCaption))
        }
    }

    @ViewBuilder
    private var shortcutsSection: some View {
        settingsStack {
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(RecordingOutputMode.allCases) { mode in
                        Text("\(mode.chordLabel)  \(mode.label) — \(mode.caption)")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AppChrome.ink)
                    }
                }
            }
            caption("全局快捷键均为「按一次开始，再按一次结束」。⌘⇧G 智能路由使用自定义 System Prompt 全权处理。")

            settingsCard {
                HStack {
                    Toggle("登录时自动启动", isOn: Binding(
                        get: { appState.launchAtLoginEnabled },
                        set: { appState.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    Spacer()
                    Text(appState.launchAtLoginMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(AppChrome.muted)
                }

                pickerRow("录音输入") {
                    Picker("", selection: $settings.inputDeviceUID) {
                        Text(defaultDeviceLabel).tag("")
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                labeledRow("当前系统播放输出", AudioInputDevices.defaultOutputName())
            }

            caption("双蓝牙用法：输入选 DJI Mic（无听筒），播放输出保持 1MORE 等耳机。App 开麦时会尽量把被 HFP 抢走的输出抢回耳机。空闲时会对蓝牙麦做短暂保活，避免「蓝牙已连接但无声音」。")

            HStack(spacing: 10) {
                secondaryPill("刷新设备") { inputDevices = AudioInputDevices.all() }
                if !appState.connectionMessage.isEmpty {
                    Text(appState.connectionMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(connectionMessageColor)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Shared chrome helpers

    private var connectionMessageColor: Color {
        AppChrome.connectionColor(for: appState.connectionMessage)
    }

    private func settingsStack(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsCard(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppChrome.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppChrome.hairline, lineWidth: 1)
        )
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppChrome.muted)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppChrome.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppChrome.hairline, lineWidth: 1)
                )
        }
    }

    private func directoryField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppChrome.muted)
            HStack(spacing: 8) {
                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppChrome.canvas)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(AppChrome.hairline, lineWidth: 1)
                    )
                secondaryPill("选择…") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = "选择"
                    if panel.runModal() == .OK, let url = panel.url {
                        text.wrappedValue = url.path
                    }
                }
            }
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppChrome.muted)
            SecureField("", text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppChrome.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppChrome.hairline, lineWidth: 1)
                )
        }
    }

    private func pickerRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.ink)
            Spacer()
            content()
        }
    }

    private func labeledRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.ink)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(AppChrome.muted)
                .multilineTextAlignment(.trailing)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(AppChrome.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func secondaryPill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppChrome.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(AppChrome.sidebarActiveFill)
                )
        }
        .buttonStyle(.plain)
    }

    private var defaultDeviceLabel: String {
        let name = AudioInputDevices.resolve(uid: "")?.name ?? "未找到输入设备"
        return "跟随系统默认（\(name)）"
    }
}
