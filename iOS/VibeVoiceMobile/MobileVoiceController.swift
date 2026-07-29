import AVFoundation
import Foundation
import WhisperKit

@MainActor
final class MobileVoiceController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case processing
        case preparingModel
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .idle: MobileL10n.t(.phaseIdle)
            case .requestingPermission: MobileL10n.t(.phaseRequestingPermission)
            case .recording: MobileL10n.t(.phaseRecording)
            case .processing: MobileL10n.t(.phaseProcessing)
            case .preparingModel: MobileL10n.t(.phasePreparingModel)
            case .ready: MobileL10n.t(.phaseReady)
            case let .failed(message): MobileL10n.t(.phaseFailed, message)
            }
        }

        /// Does not move with the device language, unlike `label`, so a log
        /// stays greppable whoever recorded it.
        var name: String {
            switch self {
            case .idle: "idle"
            case .requestingPermission: "requestingPermission"
            case .recording: "recording"
            case .processing: "processing"
            case .preparingModel: "preparingModel"
            case .ready: "ready"
            case .failed: "failed"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            var fields = ["from": oldValue.name, "to": phase.name]
            if case let .failed(message) = phase { fields["message"] = message }
            MobileLog.emit(
                .voice,
                "phase.changed",
                level: phase.name == "failed" ? .error : .info,
                fields
            )
        }
    }
    @Published private(set) var level: Float = 0
    @Published private(set) var transcript = ""
    @Published private(set) var modelStatus = MobileL10n.t(.modelNotPrepared)
    @Published private(set) var outputMode: VoiceOutputMode

    private let bridge: VoiceBridgeStore
    private let asr: any MobileASRServing
    private var recorder: (any AudioProcessing)?
    private var audioObservers: [NSObjectProtocol] = []

    init(
        bridge: VoiceBridgeStore = VoiceBridgeStore(),
        asr: any MobileASRServing = MobileASRService()
    ) {
        self.bridge = bridge
        self.asr = asr
        outputMode = bridge.load().mode
        if bridge.recoverInterruptedWork() {
            phase = .failed(MobileL10n.t(.bridgeInterrupted))
        }
        observeAudioSession()
    }

    deinit {
        let center = NotificationCenter.default
        audioObservers.forEach { center.removeObserver($0) }
    }

    func prepareModel() {
        guard phase != .preparingModel, phase != .recording else { return }
        phase = .preparingModel
        modelStatus = MobileL10n.t(.preparing)
        Task {
            do {
                modelStatus = try await asr.prepare()
                phase = .idle
            } catch {
                fail(error)
                modelStatus = MobileL10n.t(.prepareFailed)
            }
        }
    }

    func startRecording() {
        guard phase != .requestingPermission,
              phase != .recording,
              phase != .processing else { return }
        phase = .requestingPermission
        Task {
            guard await AudioProcessor.requestRecordPermission() else {
                failMessage(MobileL10n.t(.microphoneDenied))
                return
            }
            do {
                let audioProcessor = AudioProcessor()
                let recording: any AudioProcessing = audioProcessor
                try recording.startRecordingLive { [weak self] buffer in
                    guard !buffer.isEmpty else { return }
                    let rms = sqrt(buffer.reduce(Float.zero) { $0 + $1 * $1 } / Float(buffer.count))
                    Task { @MainActor [weak self] in
                        self?.level = min(1, rms * 8)
                    }
                }
                recorder = recording
                transcript = ""
                phase = .recording
                bridge.publish(status: .recording, message: MobileL10n.t(.phaseRecordingOnDevice))
            } catch {
                fail(error)
            }
        }
    }

    func stopAndTranscribe() {
        guard phase == .recording, let recorder else { return }
        // Stop before reading. The capture tap appends to audioSamples from a
        // realtime audio thread, so copying a live buffer races with it and
        // also drops whatever arrives while the copy is in flight.
        recorder.stopRecording()
        let samples = Array(recorder.audioSamples)
        self.recorder = nil
        level = 0
        phase = .processing
        let mode = bridge.load().mode
        outputMode = mode
        bridge.publish(status: .processing, message: MobileL10n.t(.phaseProcessingMode, mode.label))

        Task {
            do {
                let text = try await asr.transcribe(samples: samples, mode: mode)
                transcript = text
                phase = .ready
                bridge.publish(status: .ready, text: text, message: MobileL10n.t(.phaseReturnToKeyboard))
            } catch {
                fail(error)
            }
        }
    }

    func selectOutputMode(_ mode: VoiceOutputMode) {
        outputMode = mode
        bridge.setMode(mode)
    }

    func synchronize(with state: VoiceBridgeState) {
        if outputMode != state.mode {
            outputMode = state.mode
        }
    }

    func handleBackgroundTransition() {
        // There is no background audio mode, so a recording cannot survive the
        // app leaving the foreground. End it here rather than let the session be
        // torn down under a UI that still says it is recording.
        abortRecording(reason: MobileL10n.t(.recordingStoppedInBackground))
        guard phase != .processing,
              phase != .preparingModel else { return }
        Task {
            await asr.releaseMemory()
            modelStatus = MobileL10n.t(.modelUnloaded)
        }
    }

    func reset() {
        recorder?.stopRecording()
        recorder = nil
        level = 0
        transcript = ""
        phase = .idle
        bridge.reset()
    }

    /// A call, Siri, or another app taking the audio session stops capture
    /// without telling the recorder, and losing the input route has the same
    /// effect. Without this the UI stays in `.recording` over a dead engine and
    /// the only way out is to relaunch the app.
    private func observeAudioSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        audioObservers = [
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor in
                    self?.abortRecording(reason: MobileL10n.t(.recordingInterrupted))
                }
            },
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                // Only an input that disappeared. A category change is what our
                // own capture start looks like, and reacting to it would abort
                // every recording as it begins.
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
                else { return }
                Task { @MainActor in
                    self?.abortRecording(reason: MobileL10n.t(.recordingRouteLost))
                }
            },
        ]
    }

    private func abortRecording(reason: String) {
        guard phase == .recording else { return }
        failMessage(reason)
    }

    private func fail(_ error: Error) {
        failMessage(error.localizedDescription)
    }

    private func failMessage(_ message: String) {
        recorder?.stopRecording()
        recorder = nil
        level = 0
        phase = .failed(message)
        bridge.publish(status: .failed, message: message)
    }
}
