import Foundation

enum StreamingASREvent: Equatable, Sendable {
    case partial(String)
    case stable(String)
    case final(String)
    case error(String)
    case usage(TokenUsage)
    case done
}

protocol StreamingASRClient: Sendable {
    /// Push Int16 LE PCM @ 16 kHz mono. No-op for result-only clients.
    func appendPCM(_ frame: Data) async throws
    /// Signal end of utterance / session and await final transcript.
    func finish() async throws -> String
    /// Cancel in-flight work.
    func cancel() async
}

/// Callback sink used by clients that emit interim text while working.
typealias StreamingASRPartialHandler = @Sendable (StreamingASREvent) -> Void
