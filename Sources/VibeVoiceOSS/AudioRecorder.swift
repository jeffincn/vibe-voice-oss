import AVFoundation
import CoreAudio
import Foundation
import ObjCExceptionCatcher

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case noSamples
    case noAudibleSignal(device: String)
    case invalidInputFormat(device: String)
    case tapInstallFailed(device: String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "没有麦克风权限，请在系统设置中允许 Vibe Voice OSS 使用麦克风。"
        case .noSamples: "没有录到有效音频。"
        case let .noAudibleSignal(device):
            "没有从“\(device)”检测到声音。请检查麦克风是否静音、发射器是否连接，或在系统声音设置中切换输入设备。"
        case let .invalidInputFormat(device):
            "录音设备“\(device)”尚未就绪（采样率无效）。请稍候再试，或在设置中重新选择麦克风。"
        case let .tapInstallFailed(device):
            "无法开始使用“\(device)”录音（输入格式不兼容）。请尝试重新插拔设备，或先在系统声音设置中选中该麦克风后再试。"
        }
    }
}

final class AudioRecorder: @unchecked Sendable {
    var onLevel: ((Float) -> Void)?
    var onBands: ((AudioBands) -> Void)?
    /// Int16 little-endian PCM frames at 16 kHz mono (≈20–40 ms).
    var onPCMFrame: ((Data) -> Void)?

    private var engine = AVAudioEngine()
    private let sessionLock = NSLock()

    /// Everything past the raw de-interleave runs here.
    ///
    /// The tap closure is called on a real-time audio thread. It used to take a
    /// mutex that `stop()`, `cancel()` and device switching also take on the main
    /// thread, which is a priority inversion: the render thread waits on a
    /// lower-priority thread, misses its deadline, and the audio unit answers with
    /// a dropout. Serial dispatch keeps the ordering the ring logic depends on
    /// while leaving the render thread free.
    private let processingQueue = DispatchQueue(
        label: "app.vibevoice.oss.audio-processing",
        qos: .userInitiated
    )
    /// Snapshot taken when a session starts, so reading a handler on the processing
    /// queue cannot race a reassignment.
    private var activeHandlers = Handlers()
    /// Fallback rate for buffers that arrive with an implausible format.
    private var processingInputRate: Double = 48_000

    private struct Handlers {
        var level: ((Float) -> Void)?
        var bands: ((AudioBands) -> Void)?
        var pcm: ((Data) -> Void)?
    }

    /// Final capture buffer, already downsampled to 16 kHz mono. Owned by `processingQueue`.
    private var samples: [Float] = []
    /// Safety ceiling (~30 min @ 16 kHz) so a forgotten session cannot exhaust memory.
    private let maxFinalSamples = 16_000 * 60 * 30
    private var sampleRate: Double = 48_000
    private var activeDeviceName = "系统默认麦克风"
    private var resampler = StreamingResampler(inputRate: 48_000)
    private var pcmCarry = Data()
    private var smoothedBands = AudioBands.silent
    /// Target frame size: 40 ms @ 16 kHz → 640 samples → 1280 bytes.
    private let pcmFrameBytes = 640 * 2
    /// `removeTap` / second `installTap` both abort if the tap state is wrong — track it.
    private var isTapInstalled = false
    /// Node that currently owns the tap (`inputNode` or an intermediate mixer).
    private weak var tapNode: AVAudioNode?
    private var routeRestoreGeneration = 0
    /// System default input from before this session repointed it.
    private var preservedInputDeviceID: AudioDeviceID?
    /// Bumped on every tear-down so a delayed start won't installTap on a replaced engine.
    private var engineGeneration = 0
    private var boundDeviceID: AudioDeviceID?
    init() {
        AudioInputDevices.ensureDeviceChangeSubscription()
    }

    func deviceName(for uid: String) -> String {
        AudioInputDevices.resolve(uid: uid)?.name ?? "未连接的麦克风"
    }

    func start(deviceUID: String = "") async throws {
        guard await requestMicrophoneAccess() else {
            throw AudioRecorderError.microphoneDenied
        }

        let requestedName = deviceUID.isEmpty ? "系统默认麦克风" : deviceUID

        // A USB device that just reconnected (or woke from sleep) briefly exposes a
        // dead or transitioning HAL object. Re-resolve by UID on every attempt so a
        // fresh AudioDeviceID is used, and retry binds that fail with a stale handle.
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

    /// Put the system default input back where the user had it. Choosing a mic in this
    /// app should not decide which microphone Zoom or FaceTime picks up afterwards.
    private func restoreSystemInputRoute() {
        let preserved: AudioDeviceID? = sessionLock.withLock {
            defer { preservedInputDeviceID = nil }
            return preservedInputDeviceID
        }
        AudioInputDevices.restoreInputRoute(preserved)
    }

    private func startSession(device: AudioInputDevice) async throws {
        // Bluetooth HFP mics (e.g. DJI Mic Mini) often steal system output when opened.
        // Capture headphones first, then restore after binding input + starting the engine.
        let preservedOutput = AudioInputDevices.captureOutputRoute()

        // Only on the first switch of a session — a retry must not record the device we
        // just selected ourselves as the one to put back.
        sessionLock.withLock {
            if preservedInputDeviceID == nil {
                preservedInputDeviceID = AudioInputDevices.defaultInputDeviceID()
            }
        }

        // Pin system default *input* before (re)creating the engine so the IO unit
        // wakes up on the selected hardware. Changing the device then immediately
        // calling installTap with a stale/zero format aborts in AVFAudio.
        _ = AudioInputDevices.setDefaultInputDevice(device.id)
        _ = AudioInputDevices.restoreOutputRoute(preservedOutput)

        let generation: Int = try sessionLock.withLock {
            tearDownEngineLocked()
            try bindInputDeviceLocked(device)
            activeDeviceName = device.name
            return engineGeneration
        }

        // USB devices (e.g. AB13X) require tap.sampleRate == hardware input sampleRate.
        // Wait for a valid *hardware* inputFormat before installing.
        let hwFormat = try await waitForValidHardwareFormat(
            deviceName: device.name,
            expectedGeneration: generation
        )

        try sessionLock.withLock {
            guard generation == engineGeneration else {
                throw AudioRecorderError.invalidInputFormat(device: device.name)
            }
            if boundDeviceID != device.id {
                try bindInputDeviceLocked(device)
            }

            let input = engine.inputNode
            let liveHW = input.inputFormat(forBus: 0)
            let hardware = Self.isValidCaptureFormat(liveHW) ? liveHW : hwFormat
            guard Self.isValidCaptureFormat(hardware) else {
                throw AudioRecorderError.invalidInputFormat(device: device.name)
            }

            sampleRate = hardware.sampleRate
            try installCaptureTapLocked(hardware: hardware, deviceName: device.name)

            // After the tap, because it settles on the rate the tap was accepted at.
            // The engine is not running yet, so no buffer can arrive mid-reset.
            let configuredRate = sampleRate
            let handlers = Handlers(level: onLevel, bands: onBands, pcm: onPCMFrame)
            processingQueue.sync {
                samples.removeAll(keepingCapacity: true)
                pcmCarry.removeAll(keepingCapacity: true)
                smoothedBands = .silent
                processingInputRate = configuredRate
                activeHandlers = handlers
                resampler = StreamingResampler(inputRate: configuredRate)
            }

            do {
                engine.prepare()
                try engine.start()
            } catch {
                tearDownEngineLocked()
                throw error
            }

            // engine.start() is when macOS often flips BT output to the HFP mic — put headphones back.
            _ = AudioInputDevices.restoreOutputRoute(preservedOutput)
            routeRestoreGeneration += 1
            let restoreGeneration = routeRestoreGeneration
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard restoreGeneration == self.routeRestoreGeneration else { return }
                _ = AudioInputDevices.restoreOutputRoute(preservedOutput)
            }
        }
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

    /// Prefer hardware `inputFormat` for the tap — USB mics reject taps whose rate
    /// differs from HW (`format.sampleRate == inputHWFormat.sampleRate`).
    /// Fall back to a muted mixer bridge when direct tap still fails.
    private func installCaptureTapLocked(hardware: AVAudioFormat, deviceName: String) throws {
        let input = engine.inputNode
        let candidates = Self.tapFormatCandidates(hardware: hardware, input: input)

        for format in candidates {
            if performInstallTap(on: input, format: format) {
                sampleRate = format.sampleRate
                return
            }
        }

        // Mixer path: connect with HW format, tap float PCM at the same rate.
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
            throw AudioRecorderError.tapInstallFailed(device: deviceName)
        }
        guard performInstallTap(on: mixer, format: mixerTap) else {
            tearDownEngineLocked()
            throw AudioRecorderError.tapInstallFailed(device: deviceName)
        }
        sampleRate = mixerTap.sampleRate
    }

    private static func tapFormatCandidates(
        hardware: AVAudioFormat,
        input: AVAudioInputNode
    ) -> [AVAudioFormat] {
        var formats: [AVAudioFormat] = [hardware]
        let output = input.outputFormat(forBus: 0)
        // outputFormat is only safe when rate + channels match HW exactly.
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
                self?.append(buffer: buffer)
            }
        }, &tapError)
        if installed {
            tapNode = node
            isTapInstalled = true
            return true
        }
        return false
    }

    /// Poll until hardware `inputFormat` is usable after a device switch.
    private func waitForValidHardwareFormat(
        deviceName: String,
        expectedGeneration: Int
    ) async throws -> AVAudioFormat {
        let attempts = 40
        for attempt in 0..<attempts {
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
            if let candidate {
                return candidate
            }
            let cancelled = sessionLock.withLock { expectedGeneration != engineGeneration }
            if cancelled {
                throw AudioRecorderError.invalidInputFormat(device: deviceName)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw AudioRecorderError.invalidInputFormat(device: deviceName)
    }

    private static func isValidCaptureFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate >= 8_000 && format.channelCount >= 1
    }

    func stop() throws -> Data {
        sessionLock.withLock { tearDownEngineLocked() }
        restoreSystemInputRoute()
        // Removing the tap first means this sync drains every buffer already handed to
        // the queue. Reading before the tear-down dropped whatever was still in flight,
        // which is the tail of the recording — usually the last word.
        let recorded: [Float] = processingQueue.sync {
            let recorded = samples
            samples.removeAll(keepingCapacity: false)
            pcmCarry.removeAll(keepingCapacity: false)
            smoothedBands = .silent
            return recorded
        }
        guard !recorded.isEmpty else { throw AudioRecorderError.noSamples }

        let peak = recorded.reduce(Float.zero) { max($0, abs($1)) }
        guard peak >= 0.001 else {
            throw AudioRecorderError.noAudibleSignal(device: activeDeviceName)
        }

        let meanSquare = recorded.reduce(Float.zero) { $0 + $1 * $1 } / Float(recorded.count)
        let gain = Self.exportGain(rms: sqrt(meanSquare), peak: peak)
        let normalized = recorded.map { max(-1, min(1, $0 * gain)) }
        // `recorded` is already 16 kHz mono, so encoding is a header wrap (no second resample).
        return WAVEncoder.encode(samples: normalized, inputSampleRate: Double(WAVEncoder.outputSampleRate))
    }

    /// Boost a quiet capture toward -20 dBFS for export.
    ///
    /// The RMS target alone is not enough: a recording whose peak sits far above its
    /// average — a quiet voice plus one cough or desk knock — asked for the full 8x and
    /// clipped everything above -18 dBFS into a square wave. Limiting by the headroom
    /// the loudest sample leaves means the boost can never reach the clamp.
    static func exportGain(rms: Float, peak: Float) -> Float {
        let towardTarget = min(8, 0.1 / max(rms, 0.000_01))
        let headroom = 0.98 / max(peak, 0.000_01)
        return max(1, min(towardTarget, headroom))
    }

    /// Discard an in-progress capture without requiring samples (e.g. superseded start).
    func cancel() {
        sessionLock.withLock { tearDownEngineLocked() }
        restoreSystemInputRoute()
        processingQueue.sync {
            samples.removeAll(keepingCapacity: false)
            pcmCarry.removeAll(keepingCapacity: false)
            smoothedBands = .silent
        }
    }

    private func tearDownEngineLocked() {
        routeRestoreGeneration += 1
        engineGeneration += 1
        boundDeviceID = nil
        if engine.isRunning {
            engine.stop()
        }
        if isTapInstalled {
            (tapNode ?? engine.inputNode).removeTap(onBus: 0)
            isTapInstalled = false
        }
        tapNode = nil
        // Fresh engine avoids AVAudioEngine tap-state desync that aborts on re-install.
        engine = AVAudioEngine()
    }

    /// Tap callback. Runs on a real-time audio thread with a hard deadline, so it does
    /// the one thing that cannot be deferred — copying out of a buffer the tap reclaims
    /// as soon as this returns — and hands the rest to `processingQueue`.
    private func append(buffer: AVAudioPCMBuffer) {
        guard let mono = AudioBufferDownmix.mono(from: buffer) else { return }
        let bufferRate = buffer.format.sampleRate
        processingQueue.async { [weak self] in
            self?.process(mono: mono, tapRate: bufferRate)
        }
    }

    /// Level metering, band smoothing, resampling and PCM framing. Owns every piece of
    /// mutable capture state, so it must only ever run on `processingQueue`.
    private func process(mono: [Float], tapRate: Double) {
        dispatchPrecondition(condition: .onQueue(processingQueue))
        let frameCount = mono.count
        guard frameCount > 0 else { return }

        // Keep the resampler aligned with whatever format the tap actually delivers,
        // which is not always the format the engine reported at install time.
        if tapRate >= 8_000 {
            processingInputRate = tapRate
        }

        let meanSquare = mono.reduce(0) { $0 + $1 * $1 } / Float(frameCount)
        let rms = sqrt(meanSquare)
        // Map typical speech (-45...-8 dBFS) into a useful, gently compressed 0...1 range.
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalizedLevel = max(0, min(1, (decibels + 45) / 37))
        activeHandlers.level?(normalizedLevel)

        let rawBands = AudioBandEstimator.estimate(samples: mono)
        smoothedBands = AudioBandEstimator.follow(current: smoothedBands, target: rawBands)
        activeHandlers.bands?(smoothedBands)

        resampler.updateInputRate(processingInputRate)
        let resampled = resampler.push(mono)
        // Store the final audio already downsampled to 16 kHz — keeping the 48 kHz stream
        // for the whole session tripled memory and forced a second full resample at stop().
        // Bounded so a runaway-long session degrades gracefully instead of exhausting memory.
        if samples.count < maxFinalSamples, !resampled.isEmpty {
            let room = maxFinalSamples - samples.count
            samples.append(contentsOf: resampled.count <= room ? resampled : Array(resampled.prefix(room)))
        }
        pcmCarry.append(StreamingResampler.int16LE(from: resampled))
        let wholeFrames = (pcmCarry.count / pcmFrameBytes) * pcmFrameBytes
        guard wholeFrames > 0 else { return }
        // Rebuild both sides so Data.startIndex stays 0 — repeated removeFirst() drifts
        // startIndex and later 0-based slicing traps on long recordings.
        let emitted = Data(pcmCarry.prefix(wholeFrames))
        pcmCarry = Data(pcmCarry.suffix(pcmCarry.count - wholeFrames))

        var offset = 0
        while offset + pcmFrameBytes <= emitted.count {
            activeHandlers.pcm?(emitted.subdata(in: offset..<(offset + pcmFrameBytes)))
            offset += pcmFrameBytes
        }
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
