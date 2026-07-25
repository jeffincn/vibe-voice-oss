import Foundation

enum KeyboardLanguage: String, Codable, CaseIterable, Sendable {
    case chinese
    case english

    var toggleLabel: String {
        switch self {
        case .chinese: "中"
        case .english: "EN"
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
        case .original: "原文"
        case .polished: "整理"
        case .translate: "翻译"
        }
    }
}
