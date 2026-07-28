import Carbon.HIToolbox
import Foundation

/// Output pipeline invoked by a global recording shortcut.
enum RecordingOutputMode: String, CaseIterable, Identifiable, Sendable {
    case conversation
    case english
    case structured
    case prompt
    case smartRoute

    var id: String { rawValue }

    var label: String {
        switch self {
        case .conversation: L10n.t(.modeConversation)
        case .english: L10n.t(.modeEnglish)
        case .structured: L10n.t(.modeStructured)
        case .prompt: L10n.t(.modePrompt)
        case .smartRoute: L10n.t(.modeSmartRoute)
        }
    }

    var caption: String {
        switch self {
        case .conversation: L10n.t(.modeConversationCaption)
        case .english: L10n.t(.modeEnglishCaption)
        case .structured: L10n.t(.modeStructuredCaption)
        case .prompt: L10n.t(.modePromptCaption)
        case .smartRoute: L10n.t(.modeSmartRouteCaption)
        }
    }

    /// Display chord, e.g. ⌘⇧R.
    var chordLabel: String {
        switch self {
        case .conversation: "⌘⇧R"
        case .english: "⌘⇧E"
        case .structured: "⌘⇧F"
        case .prompt: "⌘⇧T"
        case .smartRoute: "⌘⇧G"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .conversation: UInt32(kVK_ANSI_R)
        case .english: UInt32(kVK_ANSI_E)
        case .structured: UInt32(kVK_ANSI_F)
        case .prompt: UInt32(kVK_ANSI_T)
        case .smartRoute: UInt32(kVK_ANSI_G)
        }
    }

    var carbonModifiers: UInt32 { UInt32(cmdKey | shiftKey) }

    /// Carbon EventHotKeyID.id — must be unique per chord.
    var carbonHotKeyID: UInt32 {
        switch self {
        case .conversation: 1
        case .english: 4
        case .structured: 2
        case .prompt: 3
        case .smartRoute: 5
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

    var pressHint: String { L10n.t(.pressHotKey, label) }

    var toggleHint: String { L10n.t(.toggleHotKeyHint, label) }
}
