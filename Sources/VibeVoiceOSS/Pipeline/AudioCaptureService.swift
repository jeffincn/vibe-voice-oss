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
        case .microphoneDenied:
            "没有麦克风权限，请在系统设置中允许 Vibe Voice OSS 使用麦克风。"
        case let .invalidInputFormat(device):
            "录音设备“\(device)”尚未就绪（采样率无效）。"
        case let .tapInstallFailed(device):
            "无法开始使用“\(device)”录音（输入格式不兼容）。"
        }
    }
}

/// Continuous AVAudioEngine capture that streams 16 kHz mono Float frames (no full-session buffer).
final class AudioCaptureService: @unchecked Sendable {
    /// Called on the audio tap thread with 16 kHz mono samples and RMS.
    var onSamples: (([Float], Float) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onBands: ((AudioBands) -> Void)?

    private var engine = AVAudioEngine()
    private let sessionLock = NSLock()
    private var converter = AudioFormatConverter()
    private var sampleRate: Double = 48_000
    private(set) var activeDeviceName = "系统默认麦克风"
    private(set) var hardwareSampleRate: Double = 48_000
    private let voiceProcessing = AppleVoiceProcessingService()
    private var preferVoiceProcessing = true
    private var isTapInstalled = false
    private weak var tapNode: AVAudioNode?
    private var routeRestoreGeneration = 0
    private var engineGeneration = 0
    private var boundDeviceID: AudioDeviceID?

    var isVoiceProcessingEnabled: Bool { voiceProcessing.isEnabled }
    var voiceProcessingError: String? { voiceProcessing.lastErrorDescription }

    func start(deviceUID: String = "", enableVoiceProcessing: Bool = true) async throws {
        preferVoiceProcessing = enableVoiceProcessing
        guard await requestMicrophoneAccess() else {
            throw AudioCaptureServiceError.microphoneDenied
        }

        let requestedName = deviceUID.isEmpty ? "系统默认麦克风" : deviceUID
        guard let device = AudioInputDevices.resolve(uid: deviceUID) else {
            throw AudioInputDeviceError.unavailable(requestedName)
        }

        let preservedOutput = AudioInputDevices.captureOutputRoute()
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
            converter.reset(inputSampleRate: sampleRate)

            try installCaptureTapLocked(hardware: hardware, deviceName: device.name)

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

    private func handleTap(buffer: AVAudioPCMBuffer) {
        let (samples, rms) = sessionLock.withLock { () -> ([Float], Float) in
            converter.convert(buffer: buffer)
        }
        guard !samples.isEmpty else { return }

        let decibels = 20 * log10(max(rms, 0.000_01))
        let normalizedLevel = max(0, min(1, (decibels + 45) / 37))
        onLevel?(normalizedLevel)
        onBands?(AudioBandEstimator.estimate(samples: samples))
        onSamples?(samples, rms)
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
