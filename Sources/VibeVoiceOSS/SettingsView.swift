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
                Toggle(L10n.t(.voicePipeline), isOn: $settings.voicePipelineEnabled)
                    .toggleStyle(.switch)
                    .disabled(!settings.isVoicePipelineAvailable)
                if settings.isVoicePipelineAvailable {
                    caption(L10n.t(.voicePipelineCaption))
                } else {
                    caption(L10n.t(.voicePipelineUnavailable))
                }
                if settings.asrBackend == .integrated {
                    pickerRow(L10n.t(.settingsEngine)) {
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
                        field(L10n.t(.settingsQwenRepo), text: $settings.qwenModelRepo)
                        caption(L10n.t(.qwenRepoCaption))
                        directoryField(L10n.t(.settingsModelPath), text: $settings.integratedASRModelPath)
                        caption(L10n.t(.currentModel, settings.qwenModelRepo))
                        caption(L10n.t(.modelFilesCaption))
                    } else {
                        field(L10n.t(.settingsWhisperKitModel), text: $settings.whisperKitModel)
                        caption(L10n.t(.currentModel, "WhisperKit · \(settings.whisperKitModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tiny" : settings.whisperKitModel)"))
                        caption(L10n.t(.modelFilesCaption))
                    }
                    field("HF \(L10n.t(.settingsEndpoint))", text: $settings.hfEndpoint)
                    caption(L10n.t(.hfEndpointCaption))
                } else {
                    field(L10n.t(.settingsEndpoint), text: $settings.endpoint)
                    cleartextEndpointWarning(settings.endpoint)
                    secureField(L10n.t(.apiKeyOptional), text: $settings.apiKey)
                    field(L10n.t(.settingsModel), text: $settings.model)
                }
                field(L10n.t(.recognitionLanguage), text: $settings.language)
                caption(L10n.t(.recognitionLanguageCaption))
            }

            if settings.asrBackend == .api {
                caption(L10n.t(.modelNameMatchCaption))
                caption(L10n.t(.liveCaptionCaption))

                settingsCard {
                    pickerRow(L10n.t(.recognitionMode)) {
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
                        caption(L10n.t(.streamingFallbackCaption))
                    }
                }
            } else {
                caption(L10n.t(.integratedNoStreamingCaption))
            }

            HStack(spacing: 10) {
                if settings.asrBackend == .integrated {
                    if appState.isPreparingLocalASRModel {
                        secondaryPill(L10n.t(.cancelDownload)) { appState.cancelLocalASRModelPreparation() }
                    } else {
                        secondaryPill(L10n.t(.settingsPrepareModel)) { appState.prepareLocalASRModel() }
                    }
                }
                secondaryPill(settings.asrBackend == .integrated ? L10n.t(.checkLocalASR) : L10n.t(.settingsTestASR)) {
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
                pickerRow(L10n.t(.settingsTranscodeProfile)) {
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
                labeledRow(L10n.t(.sampleRate), "\(settings.transcodeProfile.sampleRate) Hz")
                labeledRow(L10n.t(.channels), "\(settings.transcodeProfile.channels)")
                labeledRow(
                    L10n.t(.codec),
                    "\(settings.transcodeProfile.container) / \(settings.transcodeProfile.codec) · \(settings.transcodeProfile.bitDepth)-bit"
                )
                Toggle(L10n.t(.settingsNormalize), isOn: $settings.transcodeNormalize)
                    .toggleStyle(.switch)
                HStack {
                    Text(L10n.t(.maxGain))
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
                pickerRow(L10n.t(.settingsLLMBackend)) {
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
                field(L10n.t(.settingsLLMEndpoint), text: $settings.llmEndpoint)
                    .disabled(settings.llmBackend != .api)
                if settings.llmBackend == .api {
                    cleartextEndpointWarning(settings.llmEndpoint)
                }
                secureField(L10n.t(.apiKeyOptional), text: $settings.llmApiKey)
                    .disabled(settings.llmBackend != .api)
                field(L10n.t(.settingsLLMModel), text: $settings.translationModel)
                    .disabled(settings.llmBackend != .api)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t(.customPrompt))
                        .font(.system(size: 12, weight: .medium))
                    TextEditor(text: $settings.llmSystemPrompt)
                        .font(.system(size: 13))
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(AppChrome.canvas, in: RoundedRectangle(cornerRadius: 8))
                }
                .disabled(settings.llmBackend != .api)
                caption(L10n.t(.customPromptCaption))

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t(.outputLanguageCombination))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppChrome.ink)
                    caption(L10n.t(.outputLanguageCombinationCaption))
                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(TargetLanguage.translationOptions) { language in
                            targetLanguageToggle(language)
                        }
                    }
                    if settings.targetLanguages.contains(where: { $0.id == "ja" }) {
                        caption(TranslationClient.supportsJapaneseNaturalTranslation(model: settings.translationModel)
                            ? L10n.t(.japaneseNaturalCaption)
                            : L10n.t(.japaneseModelRequirement))
                    }
                }
                .disabled(!settings.llmFeaturesAvailable)
            }

            if settings.llmBackend == .api {
                caption(L10n.t(.llmModelKeyCaption))
                caption(L10n.t(.providerProfileCaption))
                caption(L10n.t(.apiKeyStorageCaption))
                if KeychainStore.usesPlaintextFallback {
                    warningCaption(L10n.t(.credentialsPlaintextWarning))
                }
            } else {
                caption(L10n.t(.llmFeaturesOffCaption))
            }

            settingsCard {
                Toggle(L10n.t(.useStructuredOutput), isOn: $settings.structuredOutputEnabled)
                    .toggleStyle(.switch)
                    .disabled(!settings.llmFeaturesAvailable)
                if settings.structuredOutputEnabled {
                    Toggle(L10n.t(.useEmoji), isOn: $settings.structuredEmojiEnabled)
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
                        ? L10n.t(.structuredEmojiCaptionOn)
                        : L10n.t(.structuredEmojiCaptionOff))
                }
                Toggle(L10n.t(.promptOptimize), isOn: $settings.promptOptimizeEnabled)
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
            caption(L10n.t(.llmOnlyWhenConfiguredCaption))
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
            caption(L10n.t(.shortcutsCaption))

            settingsCard {
                HStack {
                    Toggle(L10n.t(.settingsLaunchAtLogin), isOn: Binding(
                        get: { appState.launchAtLoginEnabled },
                        set: { appState.setLaunchAtLogin($0) }
                    ))
                    .toggleStyle(.switch)
                    Spacer()
                    Text(appState.launchAtLoginMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(AppChrome.muted)
                }

                pickerRow(L10n.t(.recordingInput)) {
                    Picker("", selection: $settings.inputDeviceUID) {
                        Text(defaultDeviceLabel).tag("")
                        ForEach(inputDevices) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                labeledRow(L10n.t(.currentPlaybackOutput), AudioInputDevices.defaultOutputName())
            }

            caption(L10n.t(.bluetoothAudioCaption))

            HStack(spacing: 10) {
                secondaryPill(L10n.t(.bluetoothRefresh)) { inputDevices = AudioInputDevices.all() }
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
                secondaryPill(L10n.t(.settingsEllipsis)) {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = L10n.t(.choose)
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

    private func targetLanguageToggle(_ language: TargetLanguage) -> some View {
        let selected = settings.isTargetLanguageSelected(language)
        return Toggle(isOn: Binding(
            get: { settings.isTargetLanguageSelected(language) },
            set: { settings.setTargetLanguageSelected(language, selected: $0) }
        )) {
            Text(language.label)
                .font(.system(size: 13))
                .foregroundStyle(AppChrome.ink)
        }
        .toggleStyle(.checkbox)
        .disabled(!selected && !settings.canSelectMoreTargetLanguages)
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

    private func warningCaption(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Shown under an endpoint field when audio / transcripts would leave the machine unencrypted.
    @ViewBuilder
    private func cleartextEndpointWarning(_ endpoint: String) -> some View {
        if EndpointSecurity.isCleartextRemote(endpoint: endpoint) {
            warningCaption(L10n.t(.cleartextEndpointDetail))
        }
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
        return "\(L10n.t(.settingsInputDevice))（\(name)）"
    }
}
