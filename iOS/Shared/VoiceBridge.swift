import Foundation

enum VoiceBridgeStatus: String, Codable, Sendable {
    case idle
    case requested
    case recording
    case processing
    case ready
    case consumed
    case failed
}

struct VoiceBridgeState: Codable, Equatable, Sendable {
    var requestID: UUID
    var status: VoiceBridgeStatus
    var mode: VoiceOutputMode
    var text: String
    var message: String
    var updatedAt: Date

    static var idle: VoiceBridgeState {
        VoiceBridgeState(
            requestID: UUID(),
            status: .idle,
            mode: .polished,
            text: "",
            message: "",
            updatedAt: Date()
        )
    }
}

final class VoiceBridgeStore {
    static let appGroupID = "group.app.vibevoice.oss.shared"
    private static let stateKey = "voiceBridge.state.v1"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupID)
            ?? .standard
    }

    func load() -> VoiceBridgeState {
        guard let data = defaults.data(forKey: Self.stateKey),
              let state = try? decoder.decode(VoiceBridgeState.self, from: data) else {
            return .idle
        }
        return state
    }

    @discardableResult
    func request(mode: VoiceOutputMode) -> VoiceBridgeState {
        let state = VoiceBridgeState(
            requestID: UUID(),
            status: .requested,
            mode: mode,
            text: "",
            message: "请打开 Vibe Voice 开始录音",
            updatedAt: Date()
        )
        save(state)
        return state
    }

    func publish(status: VoiceBridgeStatus, text: String = "", message: String = "") {
        var state = load()
        state.status = status
        state.text = text
        state.message = message
        state.updatedAt = Date()
        save(state)
    }

    func markConsumed(requestID: UUID) {
        var state = load()
        guard state.requestID == requestID else { return }
        state.status = .consumed
        state.updatedAt = Date()
        save(state)
    }

    func reset() {
        save(.idle)
    }

    private func save(_ state: VoiceBridgeState) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: Self.stateKey)
    }
}
