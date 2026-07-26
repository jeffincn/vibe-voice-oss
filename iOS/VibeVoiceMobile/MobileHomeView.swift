import SwiftUI

struct MobileHomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var bridgeState = VoiceBridgeState.idle
    @State private var bridgeWatcher: VoiceBridgeWatcher?
    @State private var rimeStatus = MobileL10n.t(.modelNotPrepared)
    @State private var isPreparingRime = false
    @StateObject private var voiceController = MobileVoiceController()
    private let bridge = VoiceBridgeStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    setupCard
                    playgroundCard
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
            Text(MobileL10n.t(.homeHero))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(MobileL10n.t(.homeEnableKeyboardTitle), systemImage: "keyboard")
                .font(.headline)
            Text(MobileL10n.t(.homeEnableKeyboardBody))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var playgroundCard: some View {
        NavigationLink {
            InputPlaygroundView(voiceController: voiceController)
        } label: {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(MobileL10n.t(.playgroundTitle))
                            .font(.headline)
                        Text(MobileL10n.t(.playgroundSubtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                } icon: {
                    Image(systemName: "message.and.waveform")
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playground.open")
        .cardStyle()
    }

    private var bridgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(MobileL10n.t(.homeBridgeTitle), systemImage: "mic.fill")
                    .font(.headline)
                Spacer()
                Text(bridgeState.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(voiceController.phase.label)
                .font(.subheadline.weight(.medium))
            Picker(MobileL10n.t(.homeOutputTitle), selection: Binding(
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
                Button(voiceController.phase == .recording
                    ? MobileL10n.t(.homeStopAndTranscribe)
                    : MobileL10n.t(.homeStartRecording)) {
                    if voiceController.phase == .recording {
                        voiceController.stopAndTranscribe()
                    } else {
                        voiceController.startRecording()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("voice.record")
                Button(MobileL10n.t(.homeBridgeReset)) {
                    voiceController.reset()
                    refreshBridgeState()
                }
                .buttonStyle(.bordered)
            }
            if !voiceController.transcript.isEmpty {
                Text(voiceController.transcript)
                    .textSelection(.enabled)
            }
            Text(MobileL10n.t(.homeBridgeBody))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(MobileL10n.t(.homeOutputBody))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(MobileL10n.t(.homeLocalModelTitle), systemImage: "cpu")
                .font(.headline)
            LabeledContent("WhisperKit tiny", value: voiceController.modelStatus)
            Button(MobileL10n.t(.homeLocalModelButton)) {
                voiceController.prepareModel()
            }
            .buttonStyle(.bordered)
            .disabled(voiceController.phase == .preparingModel || voiceController.phase == .recording)
            .accessibilityIdentifier("model.prepare")
            Text(MobileL10n.t(.homeLocalModelBody))
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Qwen3-ASR", value: MobileL10n.t(.rimeExperimental))
            LabeledContent(MobileL10n.t(.rimeSectionTitle), value: rimeStatus)
            Button(isPreparingRime
                ? MobileL10n.t(.rimeDeploying)
                : MobileL10n.t(.rimeRedeploy)) {
                prepareRime(fullCheck: true)
            }
            .buttonStyle(.bordered)
            .disabled(isPreparingRime)
            Text(MobileL10n.t(.rimeFootnote))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(MobileL10n.t(.homePrivacyTitle), systemImage: "lock.shield")
                .font(.headline)
            Text(MobileL10n.t(.homePrivacyBody))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(MobileL10n.t(.homePrivacyClearButton), role: .destructive) {
                clearSharedData()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("privacy.clear")
            Text(MobileL10n.t(.homePrivacyClearBody))
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
        rimeStatus = MobileL10n.t(.rimeLearningCleared)
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
        rimeStatus = MobileL10n.t(.preparing)
        Task {
            let message = await Task.detached(priority: .userInitiated) {
                do {
                    _ = try RimeEngineFactory.prepareForMainApp(fullCheck: fullCheck)
                    return MobileL10n.t(.rimeReady)
                } catch {
                    return MobileL10n.t(.rimeFailed, error.localizedDescription)
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
