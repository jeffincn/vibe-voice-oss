import Foundation

public enum InputMethodVoiceStatus: String, Codable, Sendable {
    case idle, requested, recording, stopRequested, processing, ready, consumed, failed
}

public enum InputMethodVoiceMode: String, Codable, Sendable {
    case smartRoute, conversation, english, structured, prompt
}

public struct InputMethodVoiceState: Codable, Equatable, Sendable {
    public var requestID: UUID
    public var sessionID: UUID
    public var status: InputMethodVoiceStatus
    public var mode: InputMethodVoiceMode
    public var text: String
    public var message: String?
    public var updatedAt: Date

    public init(requestID: UUID = UUID(), sessionID: UUID = UUID(), status: InputMethodVoiceStatus,
                mode: InputMethodVoiceMode = .smartRoute, text: String = "", message: String? = nil,
                updatedAt: Date = Date()) {
        self.requestID = requestID; self.sessionID = sessionID; self.status = status
        self.mode = mode; self.text = text; self.message = message; self.updatedAt = updatedAt
    }

    public func isFresh(now: Date = Date()) -> Bool {
        status == .ready && now.timeIntervalSince(updatedAt) < 300
    }

    public func isExpired(now: Date = Date()) -> Bool {
        now.timeIntervalSince(updatedAt) >= 300
    }
}

public final class InputMethodBridgeStore: @unchecked Sendable {
    public static let notificationName = "app.vibevoice.oss.input-method.bridge.changed"
    public let directory: URL
    private let fileURL: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeVoiceOSS/InputMethod", isDirectory: true)
        self.directory = base
        self.fileURL = base.appendingPathComponent("voice-bridge.v1.json")
        ensureDirectory()
    }

    public func load() -> InputMethodVoiceState? {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(InputMethodVoiceState.self, from: data)
    }

    @discardableResult public func write(_ state: InputMethodVoiceState) -> Bool {
        lock.lock(); defer { lock.unlock() }
        ensureDirectory()
        guard let data = try? JSONEncoder().encode(state) else { return false }
            do {
                let tmp = fileURL.appendingPathExtension("tmp")
                try data.write(to: tmp, options: .atomic)
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp, backupItemName: nil, options: .usingNewMetadataOnly)
            } catch {
                do { try data.write(to: fileURL, options: .atomic) } catch { return false }
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        postChange()
        return true
    }

    @discardableResult public func request(mode: InputMethodVoiceMode = .smartRoute, sessionID: UUID = UUID()) -> InputMethodVoiceState {
        let state = InputMethodVoiceState(sessionID: sessionID, status: .requested, mode: mode)
        _ = write(state); return state
    }

    @discardableResult public func update(_ status: InputMethodVoiceStatus, from state: InputMethodVoiceState, text: String? = nil, message: String? = nil) -> InputMethodVoiceState {
        var next = state; next.status = status; if let text { next.text = text }; next.message = message; next.updatedAt = Date(); _ = write(next); return next
    }

    public func markConsumed(_ state: InputMethodVoiceState) { _ = update(.consumed, from: state) }

    @discardableResult public func recoverInterruptedWork(now: Date = Date()) -> InputMethodVoiceState? {
        guard let state = load(), state.isExpired(now: now),
              state.status == .requested || state.status == .recording || state.status == .stopRequested || state.status == .processing else { return nil }
        return update(.failed, from: state, message: "输入法语音请求已过期")
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if FileManager.default.fileExists(atPath: fileURL.path) { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path) }
    }

    private func postChange() {
        Self.notificationName.withCString { name in
            let cfName = CFStringCreateWithCString(nil, name, CFStringBuiltInEncodings.UTF8.rawValue)
            if let cfName { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(rawValue: cfName), nil, nil, true) }
        }
    }
}
