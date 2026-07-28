import Foundation

/// In-app UI language (independent from ASR / output language).
enum AppUILanguage: String, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }

    /// Always shown in the language’s own name (picker stays readable in either UI mode).
    var displayName: String {
        switch self {
        case .zhHans: "简体中文"
        case .english: "English"
        case .japanese: "日本語"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }

    static func resolve(id: String?) -> AppUILanguage {
        AppUILanguage(rawValue: id ?? "") ?? .zhHans
    }
}
