import SwiftUI

@main
struct VibeVoiceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.phase.symbol)
        }
        .menuBarExtraStyle(.window)

        Window("阶段耗时报告", id: "stage-timing-report") {
            StageTimingReportView()
                .environmentObject(appState)
        }
        .defaultSize(width: 560, height: 460)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

private struct MenuContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        MenuPanel(settings: appState.settings)
            .environmentObject(appState)
    }
}

private struct MenuPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var settings: AppSettings

    @State private var moreOutputExpanded = false

    private var isBusyCancelable: Bool {
        switch appState.phase {
        case .finalizing, .transcribing, .structuring, .translating, .optimizing:
            true
        default:
            false
        }
    }

    private var primaryTitle: String {
        if isBusyCancelable {
            switch appState.phase {
            case .optimizing: return "取消优化"
            case .structuring: return "取消整理"
            case .translating: return "取消翻译"
            case .finalizing: return "取消收敛"
            default: return "取消转写"
            }
        }
        return appState.phase == .recording ? "停止并转写" : "开始录音"
    }

    private var shortcutHint: String {
        RecordingOutputMode.allCases.map(\.chordLabel).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // L1 — status + primary action
            VStack(alignment: .leading, spacing: 10) {
                Label(appState.phaseLabel, systemImage: appState.phase.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppChrome.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                primaryActionButton
            }
            .appChromeCard()

            // L2 — frequent controls
            VStack(alignment: .leading, spacing: 10) {
                menuPickerRow("输出语言", systemImage: "globe") {
                    Picker("", selection: $settings.targetLanguageID) {
                        ForEach(TargetLanguage.all) { language in
                            Text(language.label).tag(language.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Toggle(isOn: $settings.promptOptimizeEnabled) {
                    Label("Prompt 优化", systemImage: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.ink)
                }
                .toggleStyle(.switch)

                if settings.promptOptimizeEnabled {
                    menuPickerRow("目标 Agent", systemImage: "cpu") {
                        Picker("", selection: $settings.promptTargetID) {
                            ForEach(PromptTargetKind.allCases) { target in
                                Text(target.label).tag(target.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
            }
            .appChromeCard()

            // L3 — collapsed advanced output options
            DisclosureGroup(isExpanded: $moreOutputExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.structuredOutputEnabled) {
                        Label("使用结构化输出", systemImage: "list.bullet.rectangle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppChrome.ink)
                    }
                    .toggleStyle(.switch)

                    if settings.structuredOutputEnabled {
                        Toggle(isOn: $settings.structuredEmojiEnabled) {
                            Label("使用 Emoji", systemImage: "face.smiling")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppChrome.ink)
                        }
                        .toggleStyle(.switch)

                        menuPickerRow("整理强度", systemImage: "slider.horizontal.3") {
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
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("更多输出选项")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppChrome.ink)
            }
            .tint(AppChrome.ink)
            .appChromeCard()

            // L4 — caption + shortcuts
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.outputCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(AppChrome.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(shortcutHint) · 详情见设置")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(AppChrome.sidebarIdle)
            }
            .padding(.horizontal, 4)

            // L5 — footer
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    appState.testConnections()
                } label: {
                    Label("测试连接", systemImage: "network")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(MenuFooterButtonStyle())
                .help("同时探测 ASR 与翻译/LLM 模型是否可达")

                if !appState.connectionMessage.isEmpty {
                    Text(appState.connectionMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(AppChrome.connectionColor(for: appState.connectionMessage))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }

                Button {
                    openWindow(id: "stage-timing-report")
                    NSApplication.shared.activate()
                } label: {
                    HStack {
                        Label("耗时统计", systemImage: "stopwatch")
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 8)
                        if let latest = appState.stageTiming.latestSession {
                            Text(latest.formattedTotal)
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(AppChrome.muted)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppChrome.sidebarIdle)
                        }
                    }
                }
                .buttonStyle(MenuFooterButtonStyle())
                .help("查看各阶段耗时，并可导出 CSV / HTML")

                Button {
                    appState.copyLastTranscript()
                } label: {
                    Label(
                        appState.transcriptCopied ? "已复制" : "复制识别文字",
                        systemImage: appState.transcriptCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(MenuFooterButtonStyle())
                .disabled(appState.lastTranscript.isEmpty)

                Button {
                    openSettings()
                    bringSettingsToFront()
                } label: {
                    Label("设置…", systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(MenuFooterButtonStyle())

                Text(AppVersion.fullLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(AppChrome.sidebarIdle)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 4)

                Divider()
                    .overlay(AppChrome.hairline)
                    .padding(.vertical, 4)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("退出 Vibe Voice")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
            }
            .appChromeCard(padding: 6)
        }
        .padding(12)
        .frame(width: 320)
        .background(AppChrome.canvas)
    }

    private var primaryActionButton: some View {
        Button {
            if isBusyCancelable {
                appState.cancelTranscription()
            } else if appState.phase == .recording {
                appState.finishRecording()
            } else {
                Task { await appState.beginRecording() }
            }
        } label: {
            Text(primaryTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Capsule(style: .continuous).fill(AppChrome.ink))
        }
        .buttonStyle(.plain)
        .modifier(PrimaryMenuShortcutModifier(
            isBusyCancelable: isBusyCancelable,
            isRecording: appState.phase == .recording
        ))
    }

    private func menuPickerRow<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppChrome.ink)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 8)
            content()
        }
    }

    private func bringSettingsToFront() {
        NSApplication.shared.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate()
            let settingsWindow = NSApplication.shared.windows.first { window in
                window.isVisible && window.level == .normal && window.canBecomeKey
            }
            settingsWindow?.makeKeyAndOrderFront(nil)
            settingsWindow?.orderFrontRegardless()
        }
    }
}

private struct MenuFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(AppChrome.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? AppChrome.sidebarActiveFill : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PrimaryMenuShortcutModifier: ViewModifier {
    let isBusyCancelable: Bool
    let isRecording: Bool

    func body(content: Content) -> some View {
        if isBusyCancelable {
            content.keyboardShortcut(.cancelAction)
        } else if !isRecording {
            content.keyboardShortcut("r")
        } else {
            content
        }
    }
}
