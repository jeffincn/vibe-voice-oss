import Foundation

enum KeyboardLanguage: String, Codable, CaseIterable, Sendable {
    case chinese
    case english

    /// Face of the language key. Always the bilingual legend — the key toggles
    /// rather than displaying the current language, which is what the badge does.
    var toggleLabel: String {
        MobileL10n.t(.keyLanguageFace)
    }

    /// Spelled out for the badge beside the composition, where there is room for
    /// a word and the one-character key label would read as decoration.
    var modeBadge: String {
        switch self {
        case .chinese: MobileL10n.t(.keyboardModePinyin)
        case .english: MobileL10n.t(.keyboardModeEnglish)
        }
    }

    mutating func toggle() {
        self = self == .chinese ? .english : .chinese
    }
}

enum VoiceOutputMode: String, Codable, CaseIterable, Sendable {
    case original
    case polished
    case translate

    var label: String {
        switch self {
        case .original: MobileL10n.t(.modeOriginal)
        case .polished: MobileL10n.t(.modePolished)
        case .translate: MobileL10n.t(.modeTranslate)
        }
    }
}

enum RimeSchema: String, CaseIterable, Hashable, Sendable {
    case simplifiedPinyin = "vibe_pinyin"
    case traditionalPinyin = "vibe_pinyin_trad_pinyin"
    case traditionalZhuyin = "vibe_zhuyin_trad"

    var label: String {
        switch self {
        case .simplifiedPinyin: "简体拼音"
        case .traditionalPinyin: "繁體拼音"
        case .traditionalZhuyin: "繁體注音"
        }
    }
}
