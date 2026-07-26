import AVFoundation
import CoreAudio
import Foundation
import ObjCExceptionCatcher

enum AudioCaptureServiceError: LocalizedError {
    case microphoneDenied
    case invalidInputFormat(device: String)
    case tapInstallFailed(device: String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: L10n.t(.errMicrophoneDenied)
        case let .invalidInputFormat(device): L10n.t(.errInvalidInputFormat, device)
        case let .tapInstallFailed(device): L10n.t(.errTapInstallFailed, device)
        }
    }
}

/// Continuous AVAudioEngine capture that streams 16 kHz mono Float frames (no full-session buffer).
final class AudioCaptureService: @unchecked Sendable {
    /// Called off the audio tap thread, in capture order, with 16 kHz mono samples and RMS.
    /// Assign before `start()`; the handlers are snapshotted when a session begins.
    var onSamples: (([Float], Float) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onBands: ((AudioBands) -> Void)?

    private var engine = AVAudioEngine()
    private let sessionLock = NSLock()

    /// Owns `converter` and the handler snapshot.
    ///
    /// The tap runs on a real-time audio thread. Taking `sessionLock` there meant the
    /// render thread could block behind `start()` / `stop()`, which hold that lock
    /// across HAL device binds and `engine.start()` — long enough to miss the render
    /// deadline and drop audio. Serial dispatch keeps frame ordering without it.
    private let processingQueue = DispatchQueue(
        label: "app.vibevoice.oss.pipeline-capture",
        qos: .userInitiated
    )
    private var converter = AudioFormatConverter()
    private var activeHandlers = Handlers()
    private var sampleRate: Double = 48_000

    private struct Handlers {
        var samples: (([Float], Float) -> Void)?
        var level: ((Float) -> Void)?
        var bands: ((AudioBands) -> Void)?
    }
    private(set) var activeDeviceName = "系统默认麦克风"
    private(set) var hardwareSampleRate: Double = 48_000
    private let voiceProcessing = AppleVoiceProcessingService()
    private var preferVoiceProcessing = true
    private var isTapInstalled = false
    private weak var tapNode: AVAudioNode?
    private var routeRestoreGeneration = 0
    /// System default input from before this session repointed it.
    private var preservedInputDeviceID: AudioDeviceID?
    private var engineGeneration = 0
    private var boundDeviceID: AudioDeviceID?

    var isVoiceProcessingEnabled: Bool { voiceProcessing.isEnabled }
    var voiceProcessingError: String? { voiceProcessing.lastErrorDescription }

    func start(deviceUID: String = "", enableVoiceProcessing: Bool = true) async throws {
        preferVoiceProcessing = enableVoiceProcessing
        AudioInputDevices.ensureDeviceChangeSubscription()
        guard await requestMicrophoneAccess() else {
            throw AudioCaptureServiceError.microphoneDenied
        }

        let requestedName = deviceUID.isEmpty ? "系统默认麦克风" : deviceUID

        // Same stale-HAL defense as AudioRecorder: re-resolve a live AudioDeviceID
        // on each attempt and retry binds that hit a dead handle after USB replug.
        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard let device = AudioInputDevices.resolveLive(uid: deviceUID) else {
                lastError = AudioInputDeviceError.unavailable(requestedName)
                continue
            }
            do {
                try await startSession(device: device)
                return
            } catch {
                lastError = error
                sessionLock.withLock { tearDownEngineLocked() }
            }
        }
        restoreSystemInputRoute()
        throw lastError ?? AudioInputDeviceError.unavailable(requestedName)
    }

    /// Put the system default input back where the user had it. Listening in this app
    /// should not decide which microphone every other app records from afterwards.
    private func restoreSystemInputRoute() {
        let preserved: AudioDeviceID? = sessionLock.withLock {
            defer { preservedInputDeviceID = nil }
            return preservedInputDeviceID
        }
        AudioInputDevices.restoreInputRoute(preserved)
    }

    private func startSession(device: AudioInputDevice) async throws {
        let preservedOutput = AudioInputDevices.captureOutputRoute()
        // Only on the first switch of a session — a retry must not record the device we
        // just selected ourselves as the one to put back.
        sessionLock.withLock {
            if preservedInputDeviceID == nil {
                preservedInputDeviceID = AudioInputDevices.defaultInputDeviceID()
            }
        }
        _ = AudioInputDevices.setDefaultInputDevice(device.id)
        _ = AudioInputDevices.restoreOutputRoute(preservedOutput)

        let generation: Int = try sessionLock.withLock {
            tearDownEngineLocked()
            try bindInputDeviceLocked(device)
            activeDeviceName = device.name
            return engineGeneration
        }

        let hwFormat = try await waitForValidHardwareFormat(
            deviceName: device.name,
            expectedGeneration: generation
        )

        try sessionLock.withLock {
            guard generation == engineGeneration else {
                throw AudioCaptureServiceError.invalidInputFormat(device: device.name)
            }
            if boundDeviceID != device.id {
                try bindInputDeviceLocked(device)
            }

            let input = engine.inputNode
            if preferVoiceProcessing {
                _ = voiceProcessing.enable(on: input)
            }

            let liveHW = input.inputFormat(forBus: 0)
            let hardware = Self.isValidCaptureFormat(liveHW) ? liveHW : hwFormat
            guard Self.isValidCaptureFormat(hardware) else {
                throw AudioCaptureServiceError.invalidInputFormat(device: device.name)
            }

            sampleRate = hardware.sampleRate
            hardwareSampleRate = hardware.sampleRate
            try installCaptureTapLocked(hardware: hardware, deviceName: device.name)

            // After the tap, because it settles on the rate the tap was accepted at.
            // The engine is not running yet, so no buffer can arrive mid-reset.
            let configuredRate = sampleRate
            let handlers = Handlers(samples: onSamples, level: onLevel, bands: onBands)
            processingQueue.sync {
                activeHandlers = handlers
                converter.reset(inputSampleRate: configuredRate)
            }

            do {
                engine.prepare()
                try engine.start()
            } catch {
                tearDownEngineLocked()
                throw error
            }

            _ = AudioInputDevices.restoreOutputRoute(preservedOutput)
            routeRestoreGeneration += 1
            let restoreGeneration = routeRestoreGeneration
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard restoreGeneration == self.routeRestoreGeneration else { return }
                _ = AudioInputDevices.restoreOutputRoute(preservedOutput)
            }

            SpeechPipelineLog.capture.info(
                "capture started device=\(self.activeDeviceName, privacy: .public) rate=\(self.hardwareSampleRate, format: .fixed(precision: 0)) vp=\(self.voiceProcessing.isEnabled)"
            )
        }
    }

    func stop() {
        sessionLock.withLock {
            tearDownEngineLocked()
        }
        restoreSystemInputRoute()
        // The tap is gone, so this drains what it already handed over and then drops the
        // handlers — nothing from the finished session can reach the segmenter afterwards.
        processingQueue.sync { activeHandlers = Handlers() }
        SpeechPipelineLog.capture.info("capture stopped")
    }

    private func bindInputDeviceLocked(_ device: AudioInputDevice) throws {
        let input = engine.inputNode
        guard let audioUnit = input.audioUnit else {
            throw AudioInputDeviceError.cannotSelect(device.name, -1)
        }
        var deviceID = device.id
        let selectionStatus = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard selectionStatus == noErr else {
            throw AudioInputDeviceError.cannotSelect(device.name, selectionStatus)
        }
        boundDeviceID = device.id
    }

    private func installCaptureTapLocked(hardware: AVAudioFormat, deviceName: String) throws {
        let input = engine.inputNode
        let candidates = Self.tapFormatCandidates(hardware: hardware, input: input)

        for format in candidates {
            if performInstallTap(on: input, format: format) {
                sampleRate = format.sampleRate
                return
            }
        }

        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(input, to: mixer, format: hardware)
        mixer.outputVolume = 0
        engine.connect(mixer, to: engine.mainMixerNode, format: hardware)
        engine.mainMixerNode.outputVolume = 0

        let mixerTap = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: hardware.sampleRate,
            channels: AVAudioChannelCount(max(1, min(2, Int(hardware.channelCount)))),
            interleaved: false
        )
        guard let mixerTap else {
            tearDownEngineLocked()
            throw AudioCaptureServiceError.tapInstallFailed(device: deviceName)
        }
        guard performInstallTap(on: mixer, format: mixerTap) else {
            tearDownEngineLocked()
            throw AudioCaptureServiceError.tapInstallFailed(device: deviceName)
        }
        sampleRate = mixerTap.sampleRate
    }

    private static func tapFormatCandidates(
        hardware: AVAudioFormat,
        input: AVAudioInputNode
    ) -> [AVAudioFormat] {
        var formats: [AVAudioFormat] = [hardware]
        let output = input.outputFormat(forBus: 0)
        if isValidCaptureFormat(output),
           abs(output.sampleRate - hardware.sampleRate) < 0.5,
           output.channelCount == hardware.channelCount,
           output != hardware {
            formats.append(output)
        }
        return formats
    }

    private func performInstallTap(on node: AVAudioNode, format: AVAudioFormat) -> Bool {
        var tapError: NSError?
        let installed = VVPerformThrowingBlock({
            node.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.handleTap(buffer: buffer)
            }
        }, &tapError)
        if installed {
            tapNode = node
            isTapInstalled = true
            return true
        }
        return false
    }

    /// Tap callback on a real-time audio thread. Downmixes out of the buffer — which the
    /// tap reclaims on return — and defers conversion and delivery to `processingQueue`.
    private func handleTap(buffer: AVAudioPCMBuffer) {
        guard let mono = AudioBufferDownmix.mono(from: buffer) else { return }
        let tapRate = buffer.format.sampleRate
        processingQueue.async { [weak self] in
            self?.process(mono: mono, tapRate: tapRate)
        }
    }

    private func process(mono: [Float], tapRate: Double) {
        dispatchPrecondition(condition: .onQueue(processingQueue))
        let (samples, rms) = converter.convert(mono: mono, tapRate: tapRate)
        guard !samples.isEmpty else { return }

        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalizedLevel = max(0, min(1, (decibels + 45) / 37))
        activeHandlers.level?(normalizedLevel)
        if let bands = activeHandlers.bands {
            bands(AudioBandEstimator.estimate(samples: samples))
        }
        activeHandlers.samples?(samples, rms)
    }

    private func waitForValidHardwareFormat(
        deviceName: String,
        expectedGeneration: Int
    ) async throws -> AVAudioFormat {
        for attempt in 0..<40 {
            let candidate: AVAudioFormat? = sessionLock.withLock {
                guard expectedGeneration == engineGeneration else { return nil }
                let hardware = engine.inputNode.inputFormat(forBus: 0)
                if Self.isValidCaptureFormat(hardware) {
                    return hardware
                }
                if attempt == 8 || attempt == 20 {
                    _ = engine.inputNode.outputFormat(forBus: 0)
                }
                return nil
            }
            if let candidate { return candidate }
            let cancelled = sessionLock.withLock { expectedGeneration != engineGeneration }
            if cancelled {
                throw AudioCaptureServiceError.invalidInputFormat(device: deviceName)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw AudioCaptureServiceError.invalidInputFormat(device: deviceName)
    }

    private func tearDownEngineLocked() {
        routeRestoreGeneration += 1
        engineGeneration += 1
        boundDeviceID = nil
        if engine.isRunning {
            engine.stop()
        }
        if isTapInstalled {
            let node = tapNode ?? engine.inputNode
            voiceProcessing.disable(on: engine.inputNode)
            node.removeTap(onBus: 0)
            isTapInstalled = false
        }
        tapNode = nil
        engine = AVAudioEngine()
    }

    private static func isValidCaptureFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate >= 8_000 && format.channelCount >= 1
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }
}
