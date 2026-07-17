import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case noSamples
    case noAudibleSignal(device: String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied: "没有麦克风权限，请在系统设置中允许 Vibe Voice OSS 使用麦克风。"
        case .noSamples: "没有录到有效音频。"
        case let .noAudibleSignal(device):
            "没有从“\(device)”检测到声音。请检查麦克风是否静音、发射器是否连接，或在系统声音设置中切换输入设备。"
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
    private var routeRestoreGeneration = 0

    func deviceName(for uid: String) -> String {
        AudioInputDevices.resolve(uid: uid)?.name ?? "未连接的麦克风"
    }

    func start(deviceUID: String = "") async throws {
        guard await requestMicrophoneAccess() else {
            throw AudioRecorderError.microphoneDenied
        }

        try sessionLock.withLock {
            // Tear down any leftover session first. A second installTap on the same bus
            // aborts the process (SIGABRT in AVFAudio) — common after a failed start or
            // overlapping hotkey / permission-probe calls.
            tearDownEngineLocked()

            // Bluetooth HFP mics (e.g. DJI Mic Mini) often steal system output when opened.
            // Capture headphones first, then restore after binding input + starting the engine.
            let preservedOutput = AudioInputDevices.captureOutputRoute()

            let input = engine.inputNode
            let requestedName = deviceUID.isEmpty ? "系统默认麦克风" : deviceUID
            guard let device = AudioInputDevices.resolve(uid: deviceUID) else {
                throw AudioInputDeviceError.unavailable(requestedName)
            }
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
            activeDeviceName = device.name

            // Pin system default *input* to this mic; do not change output here.
            _ = AudioInputDevices.setDefaultInputDevice(device.id)
            _ = AudioInputDevices.restoreOutputRoute(preservedOutput)

            let format = input.outputFormat(forBus: 0)
            sampleRate = format.sampleRate
            lock.withLock {
                samples.removeAll(keepingCapacity: true)
                pcmCarry.removeAll(keepingCapacity: true)
                smoothedBands = .silent
                resampler = StreamingResampler(inputRate: sampleRate)
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.append(buffer: buffer)
            }
            isTapInstalled = true

            do {
                engine.prepare()
                try engine.start()
            } catch {
                tearDownEngineLocked()
                throw error
            }

            // engine.start() is when macOS often flips BT output to the HFP mic — put headphones back.
            _ = AudioInputDevices.restoreOutputRoute(preservedOutput)
            // One deferred pass covers late profile renegotiation.
            routeRestoreGeneration += 1
            let generation = routeRestoreGeneration
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard generation == self.routeRestoreGeneration else { return }
                _ = AudioInputDevices.restoreOutputRoute(preservedOutput)
            }
        }
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
        if engine.isRunning {
            engine.stop()
        }
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        // Fresh engine avoids AVAudioEngine tap-state desync that aborts on re-install.
        engine = AVAudioEngine()
    }

    private func append(buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else { return }

        var mono = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            let source = channels[channel]
            for frame in 0..<frameCount {
                mono[frame] += source[frame] / Float(channelCount)
            }
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
