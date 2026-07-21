import Foundation

/// How ASR results are produced for a recording session.
enum StreamingMode: String, CaseIterable, Identifiable, Sendable {
    /// Stop → upload full WAV → wait for complete JSON (legacy).
    case batch
    /// Stop → upload full WAV with `stream=true`; render SSE deltas when the server supports them.
    case sseResult
    /// While recording, push PCM frames and show interim text (WebSocket, with overlapping-window fallback).
    case duplexStreaming

    var id: String { rawValue }

    var label: String {
        switch self {
        case .batch: L10n.t(.streamingBatch)
        case .sseResult: L10n.t(.streamingSSE)
        case .duplexStreaming: L10n.t(.streamingDuplex)
        }
    }

    var caption: String {
        switch self {
        case .batch: L10n.t(.streamingBatchCaption)
        case .sseResult: L10n.t(.streamingSSECaption)
        case .duplexStreaming: L10n.t(.streamingDuplexCaption)
        }
    }

    var usesLivePartialsWhileRecording: Bool {
        self == .duplexStreaming
    }
}
