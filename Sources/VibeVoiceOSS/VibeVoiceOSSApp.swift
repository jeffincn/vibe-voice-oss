import SwiftUI

private class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowObservers: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        KeychainStore.cleanupLegacyKeychainEntries()
        // Recordings from a job that was interrupted mid-transcription otherwise
        // stay on disk forever.
        NativeASRClient.purgeAbandonedJobs()
        NSApp?.appearance = NSAppearance(named: .aqua)
        // Stay a menu-bar agent until a Settings / report window appears.
        NSApp?.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { notification in
                let window = notification.object as? NSWindow
                Task { @MainActor in
                    guard let window, AppActivation.isUserSwitcherWindow(window) else { return }
                    AppActivation.promoteForUserWindows()
                }
            },
            center.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { notification in
                let window = notification.object as? NSWindow
                Task { @MainActor in
                    guard let window, AppActivation.isUserSwitcherWindow(window) else { return }
                    AppActivation.promoteForUserWindows()
                }
            },
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in AppActivation.demoteIfNoUserWindows() }
            },
        ]
    }

    deinit {
        let center = NotificationCenter.default
        for observer in windowObservers {
            center.removeObserver(observer)
        }
    }
}

@main
struct VibeVoiceOSSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        } label: {
            Image(systemName: appState.phase.symbol)
        }
        .menuBarExtraStyle(.window)

        Window(L10n.t(.windowStageTiming), id: "stage-timing-report") {
            StageTimingReportView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 560, height: 460)

        Window(L10n.t(.windowTokenUsage), id: "token-usage-report") {
            TokenUsageReportView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 560, height: 460)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
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
        case .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing:
            true
        default:
            false
        }
    }

    private var primaryTitle: String {
        if isBusyCancelable {
            switch appState.phase {
            case .optimizing: return L10n.t(.cancelOptimize)
            case .routing: return L10n.t(.cancelRoute)
            case .structuring: return L10n.t(.cancelStructure)
            case .translating: return L10n.t(.cancelTranslate)
            case .finalizing: return L10n.t(.cancelFinalize)
            default: return L10n.t(.cancelTranscribe)
            }
        }
        return appState.phase == .recording ? L10n.t(.stopAndTranscribe) : L10n.t(.startRecording)
    }

    private var shortcutHint: String {
        RecordingOutputMode.allCases.map(\.chordLabel).joined(separator: " · ")
    }

    var body: some View {
        let _ = settings.uiLanguageID
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
                menuPickerRow(L10n.t(.outputLanguage), systemImage: "globe") {
                    Menu {
                    Text(L10n.t(.outputLanguageCombinationCaption))
                        Divider()
                        ForEach(TargetLanguage.translationOptions) { language in
                            let selected = settings.isTargetLanguageSelected(language)
                            Button {
                                settings.setTargetLanguageSelected(language, selected: !selected)
                            } label: {
                                Label(
                                    language.label,
                                    systemImage: selected ? "checkmark.circle.fill" : "circle"
                                )
                            }
                            .disabled(!selected && !settings.canSelectMoreTargetLanguages)
                        }
                    }
                    label: {
                        Text(settings.outputLanguageSummary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppChrome.ink)
                            .lineLimit(1)
                    }
                }
                .disabled(!settings.llmFeaturesAvailable)

                Toggle(isOn: $settings.promptOptimizeEnabled) {
                    Label(L10n.t(.promptOptimize), systemImage: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.ink)
                }
                .toggleStyle(.switch)
                .disabled(!settings.llmFeaturesAvailable)

                if settings.promptOptimizeEnabled && settings.llmFeaturesAvailable {
                    menuPickerRow(L10n.t(.targetAgent), systemImage: "cpu") {
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

            // L2.5 — Voice Pipeline quick toggle (kept above the collapsed section for fast access)
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { settings.voicePipelineEnabled },
                    set: { newValue in
                        settings.voicePipelineEnabled = newValue
                        appState.handleVoicePipelineSettingChanged(enabled: settings.effectiveVoicePipelineEnabled)
                    }
                )) {
                    Label(L10n.t(.voicePipeline), systemImage: "waveform.badge.mic")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.ink)
                }
                .toggleStyle(.switch)
                .disabled(!settings.isVoicePipelineAvailable)

                Text(settings.isVoicePipelineAvailable
                    ? L10n.t(.voicePipelineCaption)
                    : L10n.t(.voicePipelineUnavailable))
                    .font(.system(size: 11))
                    .foregroundStyle(AppChrome.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .appChromeCard()

            // L3 — collapsed advanced output options
            DisclosureGroup(isExpanded: $moreOutputExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $settings.structuredOutputEnabled) {
                        Label(L10n.t(.useStructuredOutput), systemImage: "list.bullet.rectangle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppChrome.ink)
                    }
                    .toggleStyle(.switch)
                    .disabled(!settings.llmFeaturesAvailable)

                    if settings.structuredOutputEnabled && settings.llmFeaturesAvailable {
                        Toggle(isOn: $settings.structuredEmojiEnabled) {
                            Label(L10n.t(.useEmoji), systemImage: "face.smiling")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(AppChrome.ink)
                        }
                        .toggleStyle(.switch)

                        menuPickerRow(L10n.t(.structureIntensity), systemImage: "slider.horizontal.3") {
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
                    if !settings.llmFeaturesAvailable {
                        Text(L10n.t(.llmNotConfiguredASROnly))
                            .font(.system(size: 11))
                            .foregroundStyle(AppChrome.muted)
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(L10n.t(.moreOutputOptions))
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

                Text("\(shortcutHint) · \(L10n.t(.detailsInSettings))")
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(AppChrome.sidebarIdle)
            }
            .padding(.horizontal, 4)

            // L5 — footer
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    appState.testConnections()
                } label: {
                    Label(L10n.t(.testConnection), systemImage: "network")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(MenuFooterButtonStyle())
                .help(L10n.t(.testConnectionHelp))

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
                    AppActivation.promoteForUserWindows()
                } label: {
                    HStack {
                        Label(L10n.t(.stageTiming), systemImage: "stopwatch")
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
                .help(L10n.t(.stageTimingHelp))

                Button {
                    openWindow(id: "token-usage-report")
                    AppActivation.promoteForUserWindows()
                } label: {
                    HStack {
                        Label(L10n.t(.tokenUsage), systemImage: "number.circle")
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 8)
                        Text(appState.tokenUsage.total.totalTokens.formatted())
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(AppChrome.muted)
                    }
                }
                .buttonStyle(MenuFooterButtonStyle())
                .help(L10n.t(.tokenUsageHelp))

                Button {
                    appState.copyLastTranscript()
                } label: {
                    Label(
                        appState.transcriptCopied ? L10n.t(.copied) : L10n.t(.copyTranscript),
                        systemImage: appState.transcriptCopied ? "checkmark" : "doc.on.doc"
                    )
                    .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(MenuFooterButtonStyle())
                .disabled(appState.lastTranscript.isEmpty)

                Button {
                    openSettings()
                    AppActivation.promoteForUserWindows()
                    bringSettingsToFront()
                } label: {
                    Label(L10n.t(.settingsEllipsis), systemImage: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(MenuFooterButtonStyle())

                Text("Vibe Voice OSS · \(AppVersion.fullLabel)")
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
                    Text(L10n.t(.quitApp))
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
        AppActivation.promoteForUserWindows()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            AppActivation.promoteForUserWindows()
            let settingsWindow = NSApplication.shared.windows.first { window in
                AppActivation.isUserSwitcherWindow(window)
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
