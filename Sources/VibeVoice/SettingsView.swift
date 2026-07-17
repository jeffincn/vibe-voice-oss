import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsForm(settings: appState.settings)
            .environmentObject(appState)
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case recognition
    case audio
    case translation
    case prompt
    case shortcuts
    case performance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recognition: "语音识别"
        case .audio: "音频转码"
        case .translation: "翻译与整理"
        case .prompt: "识别提示词"
        case .shortcuts: "快捷键与权限"
        case .performance: "性能与耗时"
        }
    }

    var symbol: String {
        switch self {
        case .recognition: "waveform"
        case .audio: "slider.horizontal.3"
        case .translation: "globe"
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

    @State private var pane: SettingsPane = .recognition
    @State private var inputDevices = AudioInputDevices.all()

    var body: some View {
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
                Text("Vibe Voice")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppChrome.ink)
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
            pillButton("打开耗时统计") {
                openWindow(id: "stage-timing-report")
                NSApplication.shared.activate()
            }
        case .recognition:
            pillButton("测试 ASR") { appState.testConnection() }
        case .translation:
            pillButton("测试翻译模型") { appState.testLanguageModelConnection() }
        case .shortcuts:
            pillButton("检查权限") { appState.requestPermissions() }
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
                    labeledRow("最近一次合计", "\(latest.formattedTotal) · \(latest.outcome.label)")
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
                caption("完成一次录音处理后，这里会显示各阶段耗时；也可导出 CSV / HTML。")
            }
        }
    }

    @ViewBuilder
    private var recognitionSection: some View {
        settingsStack {
            settingsCard {
                field("API 地址", text: $settings.endpoint)
                secureField("API Key（未启用可留空）", text: $settings.apiKey)
                field("模型名", text: $settings.model)
                field("识别语言", text: $settings.language)
            }

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
                    field("双工 WebSocket", text: $settings.streamingWSURL)
                    caption("连不上时自动降级为重叠窗伪流式（仍走本机转写接口）。")
                }
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
            caption("本地音频规格，不走远程 API。")
        }
    }

    @ViewBuilder
    private var translationSection: some View {
        settingsStack {
            settingsCard {
                field("API 地址", text: $settings.llmEndpoint)
                secureField("API Key（未启用可留空）", text: $settings.llmApiKey)
                field("模型名", text: $settings.translationModel)
                pickerRow("输出语言") {
                    Picker("", selection: $settings.targetLanguageID) {
                        ForEach(TargetLanguage.all) { language in
                            Text(language.label).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            settingsCard {
                Toggle("使用结构化输出", isOn: $settings.structuredOutputEnabled)
                    .toggleStyle(.switch)
                if settings.structuredOutputEnabled {
                    Toggle("使用 Emoji", isOn: $settings.structuredEmojiEnabled)
                        .toggleStyle(.switch)
                    pickerRow("整理强度") {
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
                    caption(settings.structureIntensity.caption)
                    caption(settings.structuredEmojiEnabled
                        ? "分区标题会带修饰性 emoji（如 ✅ 📌）。"
                        : "默认不加 emoji，只用短段与中文小标题。")
                }
                Toggle("Prompt 优化", isOn: $settings.promptOptimizeEnabled)
                    .toggleStyle(.switch)
                if settings.promptOptimizeEnabled {
                    pickerRow("目标 Agent") {
                        Picker("", selection: $settings.promptTargetID) {
                            ForEach(PromptTargetKind.allCases) { target in
                                Text(target.label).tag(target.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    caption(settings.promptTarget.caption)
                }
            }
            caption("翻译 / 结构化 / Prompt 编译共用上面的 API 地址、Key 与模型名，可与 ASR 完全不同。")
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
            caption("填写人名、项目名和技术词，使用中文逗号分隔。")
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
            caption("三个全局快捷键均为「按一次开始，再按一次结束」。菜单栏「开始录音」沿用下方开关组合。")

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
                secondaryPill("测试 oMLX 连接") { appState.testConnection() }
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
