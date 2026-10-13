import Foundation
import os

enum SpeechPipelineState: Equatable, Sendable {
    case idle
    case listening
    case speechDetected
    case speaking
    case processing
    case completed(String)
    case failed(String)
}

enum SpeechPipelineLog {
    static let subsystem = "app.vibevoice.oss.macos.pipeline"
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let voiceProcessing = Logger(subsystem: subsystem, category: "voice-processing")
    static let vad = Logger(subsystem: subsystem, category: "vad")
    static let segmenter = Logger(subsystem: subsystem, category: "segmenter")
    static let asr = Logger(subsystem: subsystem, category: "asr")
    static let coordinator = Logger(subsystem: subsystem, category: "coordinator")
}
