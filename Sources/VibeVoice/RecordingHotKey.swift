import Carbon.HIToolbox
import Foundation

/// Output pipeline invoked by a global recording shortcut.
enum RecordingOutputMode: String, CaseIterable, Identifiable, Sendable {
    case conversation
    case structured
    case prompt

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conversation: "对话"
        case .structured: "结构化"
        case .prompt: "Prompt"
        }
    }

    var caption: String {
        switch self {
        case .conversation: "按输出语言处理（翻译 / 原样）"
        case .structured: "结构化整理（沿用整理强度与 Emoji 开关）"
        case .prompt: "按 Prompt 规则编译到目标 Agent"
        }
    }

    /// Display chord, e.g. ⌘⇧R.
    var chordLabel: String {
        switch self {
        case .conversation: "⌘⇧R"
        case .structured: "⌘⇧F"
        case .prompt: "⌘⇧T"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .conversation: UInt32(kVK_ANSI_R)
        case .structured: UInt32(kVK_ANSI_F)
        case .prompt: UInt32(kVK_ANSI_T)
        }
    }

    var carbonModifiers: UInt32 { UInt32(cmdKey | shiftKey) }

    /// Carbon EventHotKeyID.id — must be unique per chord.
    var carbonHotKeyID: UInt32 {
        switch self {
        case .conversation: 1
        case .structured: 2
        case .prompt: 3
        }
    }

    static func resolve(carbonHotKeyID: UInt32) -> RecordingOutputMode? {
        allCases.first { $0.carbonHotKeyID == carbonHotKeyID }
    }

    static var shortcutLegend: String {
        allCases.map { "\($0.chordLabel) \($0.label)" }.joined(separator: " · ")
    }
}

/// Legacy single-chord model kept for older settings / tests.
struct RecordingHotKey: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let hint: String
    let keyCode: UInt32
    let carbonModifiers: UInt32

    static let all: [RecordingHotKey] = RecordingOutputMode.allCases.map { mode in
        RecordingHotKey(
            id: mode.rawValue,
            label: mode.chordLabel,
            hint: mode.caption,
            keyCode: mode.keyCode,
            carbonModifiers: mode.carbonModifiers
        )
    }

    static let defaultID = RecordingOutputMode.conversation.rawValue

    static func resolve(id: String) -> RecordingHotKey {
        all.first { $0.id == id } ?? all[0]
    }

    var pressHint: String { "按 \(label)" }

    var toggleHint: String { "\(label)（按一次开始，再按一次结束）" }
}
