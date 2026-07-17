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
        case .batch: "批处理"
        case .sseResult: "结果流式（SSE）"
        case .duplexStreaming: "双工 Streaming"
        }
    }

    var caption: String {
        switch self {
        case .batch:
            "录音时仍显示实时字幕；停录后用整段 WAV 做最终转写。"
        case .sseResult:
            "录音时显示实时字幕；停录后整段上传，若服务端支持 SSE 则渐进出最终结果。"
        case .duplexStreaming:
            "录音过程中推送 PCM 并像字幕一样显示识别文字；优先 WebSocket，否则重叠窗伪流式。"
        }
    }

    var usesLivePartialsWhileRecording: Bool {
        self == .duplexStreaming
    }
}
