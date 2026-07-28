import Foundation

/// Tiny local logger so mixed-reasoning failures are visible in Console /
/// `~/Library/Application Support/VibeVoiceOSS/Logs/ime-reason.log` without
/// needing a debugger attached to the input method.
enum ReasoningDiagnostics {
    private static let lock = NSLock()
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeVoiceOSS/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ime-reason.log")
    }()

    static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
        NSLog("[VibeReason] %@", message)
        lock.lock(); defer { lock.unlock() }
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
