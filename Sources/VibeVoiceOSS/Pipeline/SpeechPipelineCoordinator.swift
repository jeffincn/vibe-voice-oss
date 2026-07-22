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
    /// All segment texts in this listen session (one entry per VAD cut).
    @Published private(set) var segmentTexts: [String] = []

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
    /// Slow AGC so quiet mics still reach VAD/ASR (mirrors AudioRecorder export gain).
    private var agcGain: Float = 1
    /// Running transcript for ASR context across VAD cuts.
    private var accumulatedTranscript = ""
    /// Full session PCM (16 kHz) for a coherent re-ASR on stop. Capped ~3 minutes.
    private var sessionSamples: [Float] = []
    private let maxSessionSamples = 16_000 * 180

    private var isRunningFlag: Bool {
        get { stateLock.withLock { _isRunning } }
        set { stateLock.withLock { _isRunning = newValue } }
    }

    /// Joined caption text from live segments (may be choppier than full-session re-ASR).
    var joinedSegmentTranscript: String {
        segmentTexts.joined(separator: "\n")
    }

    /// Snapshot session audio for a final whole-utterance transcription.
    func takeSessionSamples() -> [Float] {
        stateLock.withLock {
            let copy = sessionSamples
            return copy
        }
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
            agcGain = 1
            accumulatedTranscript = ""
            segmentTexts = []
            stateLock.withLock { sessionSamples.removeAll(keepingCapacity: true) }

            // Levels/bands are derived from gain-normalized samples inside handleSamples
            // so the HUD matches what VAD actually hears.
            capture.onLevel = nil
            capture.onBands = nil
            capture.onSamples = { [weak self] samples, rms in
                guard let self else { return }
                self.processQueue.async {
                    self.handleSamples(samples, rms: rms)
                }
            }

            // Apple Voice Processing runs a duplex VPIO unit that only pulls mic input when the
            // engine also renders an output chain. Our capture taps the input node directly with
            // no output graph, so VPIO would start "successfully" yet deliver silence (flat level,
            // no segments). Use the plain input tap (same proven path as push-to-talk) here.
            try await capture.start(deviceUID: deviceUID, enableVoiceProcessing: false)
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
        SpeechPipelineLog.coordinator.info(
            "pipeline stopped segments=\(self.segmentTexts.count) sessionSamples=\(self.sessionSamples.count)"
        )
    }

    private func handleSamples(_ samples: [Float], rms: Float) {
        guard isRunningFlag else { return }

        // Bring quiet microphones toward ~-20 dBFS (same idea as push-to-talk WAV export).
        let targetRMS: Float = 0.1
        let instantGain = max(1, min(12, targetRMS / max(rms, 0.000_05)))
        agcGain = agcGain * 0.9 + instantGain * 0.1
        let gained: [Float]
        if agcGain <= 1.05 {
            gained = samples
        } else {
            gained = samples.map { max(-1, min(1, $0 * agcGain)) }
        }
        let gainedRMS = min(1, rms * agcGain)
        let decibels = 20 * log10(max(gainedRMS, 0.000_01))
        let normalizedLevel = max(0, min(1, (decibels + 45) / 37))
        let bands = AudioBandEstimator.estimate(samples: gained)

        SpeechPipelineLog.capture.debug(
            "rms=\(rms, format: .fixed(precision: 4)) gain=\(self.agcGain, format: .fixed(precision: 2)) n=\(samples.count)"
        )

        DispatchQueue.main.async { [weak self] in
            self?.audioLevel = normalizedLevel
            self?.audioBands = bands
        }

        stateLock.withLock {
            sessionSamples.append(contentsOf: gained)
            if sessionSamples.count > maxSessionSamples {
                sessionSamples.removeFirst(sessionSamples.count - maxSessionSamples)
            }
        }

        if let vadResult = vad.push(gained) {
            latestProbability = vadResult.speechProbability
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastSpeechProbability = vadResult.speechProbability
                self.mapVADEventToState(vadResult.event)
            }
        }

        if let segment = segmenter.push(samples: gained, speechProbability: latestProbability) {
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
        let prior = accumulatedTranscript
        let segmentIndex = segmentTexts.count + 1
        // Do not cancel an in-flight segment — that drops captions the user already spoke.
        asrTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.asr.transcribe(
                    samples: segment.samples,
                    configuration: configuration,
                    priorContext: prior
                )
                guard !Task.isCancelled else { return }
                let e2e = CFAbsoluteTimeGetCurrent() - endToEndStart
                SpeechPipelineLog.coordinator.info(
                    "segment#\(segmentIndex) asr ok e2e=\(e2e, format: .fixed(precision: 2))s asr=\(result.inferenceLatency, format: .fixed(precision: 2))s chars=\(result.text.count) priorChars=\(prior.count) text=\(result.text, privacy: .public)"
                )
                await MainActor.run {
                    self.segmentTexts.append(result.text)
                    if self.accumulatedTranscript.isEmpty {
                        self.accumulatedTranscript = result.text
                    } else {
                        self.accumulatedTranscript += "\n" + result.text
                    }
                    self.lastCompletedText = result.text
                    self.state = .completed(result.text)
                }
                // Yield so AppState's poll (and any Combine subscribers) can observe
                // `.completed` before we flip back to listening. Without this, both
                // assignments happen in one turn and the transcript never reaches the HUD.
                try? await Task.sleep(for: .milliseconds(120))
                await MainActor.run {
                    if self.isRunningFlag {
                        self.state = .listening
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                SpeechPipelineLog.coordinator.error(
                    "segment#\(segmentIndex) asr skipped: \(error.localizedDescription, privacy: .public)"
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
