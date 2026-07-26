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
            case .idle: "待机"
            case .requestingPermission: "请求麦克风权限"
            case .recording: "正在录音"
            case .processing: "正在本地转写"
            case .preparingModel: "下载并预热模型"
            case .ready: "结果已发送到键盘"
            case let .failed(message): "失败：\(message)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var transcript = ""
    @Published private(set) var modelStatus = "尚未准备"
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
            phase = .failed("上次语音任务被系统中断，请重新录音")
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
        modelStatus = "准备中"
        Task {
            do {
                modelStatus = try await asr.prepare()
                phase = .idle
            } catch {
                fail(error)
                modelStatus = "准备失败"
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
                failMessage("麦克风权限未开启")
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
                bridge.publish(status: .recording, message: "正在 iPhone 上录音")
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
        bridge.publish(status: .processing, message: "\(mode.label)模式处理中")

        Task {
            do {
                let text = try await asr.transcribe(samples: samples, mode: mode)
                transcript = text
                phase = .ready
                bridge.publish(status: .ready, text: text, message: "可返回键盘插入")
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
        abortRecording(reason: "应用切到后台，录音已停止")
        guard phase != .processing,
              phase != .preparingModel else { return }
        Task {
            await asr.releaseMemory()
            modelStatus = "已释放内存，模型保留在本机"
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
                    self?.abortRecording(reason: "录音被系统中断，请重新录音")
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
                    self?.abortRecording(reason: "录音输入设备已断开，请重新录音")
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
