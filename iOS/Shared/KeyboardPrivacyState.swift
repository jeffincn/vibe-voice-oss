import Foundation

/// Runtime capabilities for a custom keyboard. Restricted modes remain useful
/// for ordinary typing but do not inspect the host document or persist learning.
struct KeyboardPrivacyState: Equatable, Sendable {
    let hasFullAccess: Bool
    let isSecureTextEntry: Bool

    var allowsDocumentContext: Bool { hasFullAccess && !isSecureTextEntry }
    var allowsPersistentLearning: Bool { hasFullAccess && !isSecureTextEntry }
    var allowsEnhancedInference: Bool { hasFullAccess && !isSecureTextEntry }

    var status: KeyboardPrivacyStatus {
        if isSecureTextEntry { return .secureField }
        if !hasFullAccess { return .restrictedAccess }
        return .full
    }
}

enum KeyboardPrivacyStatus: Equatable, Sendable {
    case full
    case restrictedAccess
    case secureField
}
