import Foundation

/// Coordinates capture → VP → VAD → segmentation → local ASR.
/// UI should observe only `state` / level callbacks. Segment ASR failures recover to listening;
/// start failures stay in `.failed` until the user stops or retries.
final class SpeechPipelineCoordinator: ObservableObject, @unchecked Sendable {
    @Published private(set) var state: SpeechPipelineState = .idle
    @Published private(set) var audioLevel: Float = 0
    @Published private(set) var audioBands: AudioBands = .silent
    @Published private(set) var lastSpeechProbability: Float = 0
    @Published private(set) var voiceProcessingEnabled = false
    @Published private(set) var vadUsesCoreML = false
    @Published private(set) var lastCompletedText = ""

    private let capture = AudioCaptureService()
    private let vad = VADService()
    private let segmenter = SpeechSegmenter()
    private let asr = PipelineASRService()
    private let processQueue = DispatchQueue(label: "app.vibevoice.oss.pipeline.process")
    private let stateLock = NSLock()
    private var latestProbability: Float = 0
    private var _isRunning = false
    private var configuration: TranscriptionConfiguration?
    private var sessionStartedAt: CFAbsoluteTime = 0
    private var asrTask: Task<Void, Never>?

    private var isRunningFlag: Bool {
        get { stateLock.withLock { _isRunning } }
        set { stateLock.withLock { _isRunning = newValue } }
    }

    var isListening: Bool {
        switch state {
        case .listening, .speechDetected, .speaking, .processing:
            return true
        default:
            return false
        }
    }

    @MainActor
    func start(
        deviceUID: String,
        configuration: TranscriptionConfiguration
    ) async {
        guard !isRunningFlag else { return }
        self.configuration = configuration
        state = .listening // optimistic UI while preparing; rolled back on failure

        do {
            try vad.load()
            vadUsesCoreML = vad.usesCoreML
            try await asr.prepare(configuration: configuration)

            vad.reset()
            segmenter.reset()
            latestProbability = 0

            capture.onLevel = { [weak self] level in
                DispatchQueue.main.async {
                    self?.audioLevel = level
                }
            }
            capture.onBands = { [weak self] bands in
                DispatchQueue.main.async {
                    self?.audioBands = bands
                }
            }
            capture.onSamples = { [weak self] samples, rms in
                guard let self else { return }
                self.processQueue.async {
                    self.handleSamples(samples, rms: rms)
                }
            }

            do {
                try await capture.start(deviceUID: deviceUID, enableVoiceProcessing: true)
            } catch {
                SpeechPipelineLog.coordinator.error(
                    "capture with VP failed, retrying without VP: \(error.localizedDescription, privacy: .public)"
                )
                try await capture.start(deviceUID: deviceUID, enableVoiceProcessing: false)
            }
            voiceProcessingEnabled = capture.isVoiceProcessingEnabled
            sessionStartedAt = CFAbsoluteTimeGetCurrent()
            isRunningFlag = true
            state = .listening
            SpeechPipelineLog.coordinator.info(
                "pipeline listening device=\(self.capture.activeDeviceName, privacy: .public) vp=\(self.voiceProcessingEnabled) vadCoreML=\(self.vadUsesCoreML)"
            )
        } catch {
            capture.stop()
            isRunningFlag = false
            state = .failed(error.localizedDescription)
            SpeechPipelineLog.coordinator.error(
                "pipeline start failed: \(error.localizedDescription, privacy: .public)"
            )
            // Keep `.failed` visible — AppState shows the message until the user retries.
        }
    }

    @MainActor
    func stop() {
        asrTask?.cancel()
        asrTask = nil
        capture.stop()
        isRunningFlag = false
        state = .idle
        audioLevel = 0
        audioBands = .silent
        SpeechPipelineLog.coordinator.info("pipeline stopped")
    }

    private func handleSamples(_ samples: [Float], rms: Float) {
        guard isRunningFlag else { return }
        SpeechPipelineLog.capture.debug("rms=\(rms, format: .fixed(precision: 4)) n=\(samples.count)")

        if let vadResult = vad.push(samples) {
            latestProbability = vadResult.speechProbability
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastSpeechProbability = vadResult.speechProbability
                self.mapVADEventToState(vadResult.event)
            }
        }

        if let segment = segmenter.push(samples: samples, speechProbability: latestProbability) {
            DispatchQueue.main.async { [weak self] in
                self?.enqueueASR(segment: segment)
            }
        }
    }

    @MainActor
    private func mapVADEventToState(_ event: VADEvent) {
        guard isRunningFlag else { return }
        switch state {
        case .processing, .failed, .idle, .completed:
            return
        default:
            break
        }
        switch event {
        case .speechStarted:
            state = .speechDetected
        case .speechActive:
            if state == .listening || state == .speechDetected {
                state = .speaking
            }
        case .speechEnded, .silence:
            break
        }
    }

    @MainActor
    private func enqueueASR(segment: SpeechSegment) {
        guard isRunningFlag, let configuration else { return }
        state = .processing
        let endToEndStart = sessionStartedAt
        asrTask?.cancel()
        asrTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.asr.transcribe(
                    samples: segment.samples,
                    configuration: configuration
                )
                guard !Task.isCancelled else { return }
                let e2e = CFAbsoluteTimeGetCurrent() - endToEndStart
                SpeechPipelineLog.coordinator.info(
                    "segment asr ok e2e=\(e2e, format: .fixed(precision: 2))s asr=\(result.inferenceLatency, format: .fixed(precision: 2))s"
                )
                await MainActor.run {
                    self.lastCompletedText = result.text
                    self.state = .completed(result.text)
                    if self.isRunningFlag {
                        self.state = .listening
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                SpeechPipelineLog.coordinator.error(
                    "segment asr skipped: \(error.localizedDescription, privacy: .public)"
                )
                await MainActor.run {
                    // Empty / noise segments: stay listening without publishing .failed (avoids UI thrash).
                    if self.isRunningFlag {
                        self.state = .listening
                    }
                }
            }
        }
    }
}
