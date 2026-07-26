import Foundation

enum KeyboardLanguage: String, Codable, CaseIterable, Sendable {
    case chinese
    case english

    var toggleLabel: String {
        switch self {
        case .chinese: MobileL10n.t(.languageChinese)
        case .english: MobileL10n.t(.languageEnglish)
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
