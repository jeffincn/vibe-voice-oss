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
    private let lock = NSLock()
    private let sessionLock = NSLock()
    /// Final capture buffer, already downsampled to 16 kHz mono.
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
        throw lastError ?? AudioInputDeviceError.unavailable(requestedName)
    }

    private func startSession(device: AudioInputDevice) async throws {
        // Bluetooth HFP mics (e.g. DJI Mic Mini) often steal system output when opened.
        // Capture headphones first, then restore after binding input + starting the engine.
        let preservedOutput = AudioInputDevices.captureOutputRoute()

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
            lock.withLock {
                samples.removeAll(keepingCapacity: true)
                pcmCarry.removeAll(keepingCapacity: true)
                smoothedBands = .silent
                resampler = StreamingResampler(inputRate: sampleRate)
            }

            try installCaptureTapLocked(hardware: hardware, deviceName: device.name)

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
        let recorded: [Float] = sessionLock.withLock {
            let recorded = lock.withLock { samples }
            tearDownEngineLocked()
            lock.withLock {
                samples.removeAll(keepingCapacity: false)
                pcmCarry.removeAll(keepingCapacity: false)
                smoothedBands = .silent
            }
            return recorded
        }
        guard !recorded.isEmpty else { throw AudioRecorderError.noSamples }

        let peak = recorded.reduce(Float.zero) { max($0, abs($1)) }
        guard peak >= 0.001 else {
            throw AudioRecorderError.noAudibleSignal(device: activeDeviceName)
        }

        let meanSquare = recorded.reduce(Float.zero) { $0 + $1 * $1 } / Float(recorded.count)
        let rms = sqrt(meanSquare)
        // Bring quiet microphones toward -20 dBFS, capped to avoid boosting room noise excessively.
        let gain = max(1, min(8, 0.1 / max(rms, 0.000_01)))
        let normalized = recorded.map { max(-1, min(1, $0 * gain)) }
        // `recorded` is already 16 kHz mono, so encoding is a header wrap (no second resample).
        return WAVEncoder.encode(samples: normalized, inputSampleRate: Double(WAVEncoder.outputSampleRate))
    }

    /// Discard an in-progress capture without requiring samples (e.g. superseded start).
    func cancel() {
        sessionLock.withLock {
            tearDownEngineLocked()
            lock.withLock {
                samples.removeAll(keepingCapacity: false)
                pcmCarry.removeAll(keepingCapacity: false)
                smoothedBands = .silent
            }
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

    private func append(buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }

        // Keep resampler aligned with whatever format the tap actually delivers.
        let bufferRate = buffer.format.sampleRate
        if bufferRate >= 8_000, abs(bufferRate - sampleRate) > 0.5 {
            sampleRate = bufferRate
        }

        var mono = [Float](repeating: 0, count: frameCount)
        if let channels = buffer.floatChannelData {
            for channel in 0..<channelCount {
                let source = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += source[frame] / Float(channelCount)
                }
            }
        } else if let channels = buffer.int16ChannelData {
            let scale: Float = 1.0 / Float(Int16.max)
            for channel in 0..<channelCount {
                let source = channels[channel]
                for frame in 0..<frameCount {
                    mono[frame] += Float(source[frame]) * scale / Float(channelCount)
                }
            }
        } else {
            return
        }

        let meanSquare = mono.reduce(0) { $0 + $1 * $1 } / Float(frameCount)
        let rms = sqrt(meanSquare)
        // Map typical speech (-45...-8 dBFS) into a useful, gently compressed 0...1 range.
        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalizedLevel = max(0, min(1, (decibels + 45) / 37))
        onLevel?(normalizedLevel)

        let rawBands = AudioBandEstimator.estimate(samples: mono)
        let bands: AudioBands = lock.withLock {
            smoothedBands = AudioBandEstimator.follow(current: smoothedBands, target: rawBands)
            return smoothedBands
        }
        onBands?(bands)

        let pcmChunk: Data = lock.withLock {
            resampler.updateInputRate(sampleRate)
            let resampled = resampler.push(mono)
            // Store the final audio already downsampled to 16 kHz — keeping the 48 kHz stream
            // for the whole session tripled memory and forced a second full resample at stop().
            // Bounded so a runaway-long session degrades gracefully instead of exhausting memory.
            if samples.count < maxFinalSamples, !resampled.isEmpty {
                let room = maxFinalSamples - samples.count
                samples.append(contentsOf: resampled.count <= room ? resampled : Array(resampled.prefix(room)))
            }
            let encoded = StreamingResampler.int16LE(from: resampled)
            pcmCarry.append(encoded)
            let wholeFrames = (pcmCarry.count / pcmFrameBytes) * pcmFrameBytes
            guard wholeFrames > 0 else { return Data() }
            // Rebuild both sides so Data.startIndex stays 0 — repeated removeFirst() drifts
            // startIndex and later 0-based slicing traps on long recordings.
            let emitted = Data(pcmCarry.prefix(wholeFrames))
            pcmCarry = Data(pcmCarry.suffix(pcmCarry.count - wholeFrames))
            return emitted
        }
        if !pcmChunk.isEmpty {
            // Emit one concatenated blob of whole frames; session may split if needed.
            var offset = 0
            while offset + pcmFrameBytes <= pcmChunk.count {
                onPCMFrame?(pcmChunk.subdata(in: offset..<(offset + pcmFrameBytes)))
                offset += pcmFrameBytes
            }
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
