import UIKit

/// What a keyboard extension can legitimately learn about the app it is typing
/// into.
///
/// iOS deliberately exposes no host bundle identifier to a keyboard, so there
/// is no supported way to write `if host == "WeChat"`. What it does expose is
/// the shape of the text field — its traits, and how much of the document the
/// proxy will answer questions about. In practice that is what actually differs
/// between hosts, and it is what breaks insertion: an app with its own text
/// engine reports different traits and a different context window than a
/// UIKit field does.
///
/// So a "channel" here is a fingerprint of that shape. Two sessions with the
/// same `id` behave the same way as far as the keyboard is concerned; a bug
/// that reproduces under one `id` and not another is a channel-specific bug.
/// `DiagnosticSettings.channelLabel` puts a human name next to it.
struct HostChannel: Equatable, Sendable {
    var keyboardType: String
    var returnKey: String
    var autocapitalisation: String
    var autocorrection: String
    var spellChecking: String
    var appearance: String
    var documentLanguage: String
    var hasFullAccess: Bool
    /// Whether the host answered with any text before the caret. A host that
    /// returns nothing here disables candidate reranking and insertion
    /// verification, which is worth knowing before blaming either.
    var readsContextBefore: Bool
    var readsContextAfter: Bool

    /// Stable across sessions for the same kind of field, so it can group logs.
    var id: String {
        let material = [
            keyboardType, returnKey, autocapitalisation, autocorrection,
            spellChecking, appearance, documentLanguage,
            String(hasFullAccess), String(readsContextBefore), String(readsContextAfter),
        ].joined(separator: "|")
        // Not a security boundary — just a short, stable name for a tuple.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in material.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash >> 32))
    }

    var fields: [String: String] {
        [
            "channel": id,
            "kbType": keyboardType,
            "return": returnKey,
            "autocap": autocapitalisation,
            "autocorrect": autocorrection,
            "spell": spellChecking,
            "appearance": appearance,
            "docLang": documentLanguage,
            "fullAccess": String(hasFullAccess),
            "ctxBefore": String(readsContextBefore),
            "ctxAfter": String(readsContextAfter),
        ]
    }

    var summary: String {
        "\(id) · \(keyboardType)/\(returnKey) · "
            + (hasFullAccess ? "full access" : "restricted")
            + (readsContextBefore ? " · context" : " · no context")
    }

    /// Reads the traits the host published for this field.
    ///
    /// Deliberately never touches `isSecureTextEntry`. Custom keyboards are not
    /// offered for secure fields in the first place, and on iOS 26 querying
    /// that property on the proxy can trap during the extension handshake.
    @MainActor
    static func sample(
        proxy: any UITextDocumentProxy,
        hasFullAccess: Bool
    ) -> HostChannel {
        HostChannel(
            keyboardType: name(proxy.keyboardType),
            returnKey: name(proxy.returnKeyType),
            autocapitalisation: name(proxy.autocapitalizationType),
            autocorrection: name(proxy.autocorrectionType),
            spellChecking: name(proxy.spellCheckingType),
            appearance: name(proxy.keyboardAppearance),
            documentLanguage: proxy.documentInputMode?.primaryLanguage ?? "none",
            hasFullAccess: hasFullAccess,
            readsContextBefore: !(proxy.documentContextBeforeInput ?? "").isEmpty,
            readsContextAfter: !(proxy.documentContextAfterInput ?? "").isEmpty
        )
    }

    private static func name(_ value: UIKeyboardType?) -> String {
        switch value {
        case .none: "unset"
        case .some(.default): "default"
        case .some(.asciiCapable): "ascii"
        case .some(.numbersAndPunctuation): "numbersAndPunctuation"
        case .some(.URL): "url"
        case .some(.numberPad): "numberPad"
        case .some(.phonePad): "phonePad"
        case .some(.namePhonePad): "namePhonePad"
        case .some(.emailAddress): "email"
        case .some(.decimalPad): "decimalPad"
        case .some(.twitter): "twitter"
        case .some(.webSearch): "webSearch"
        case .some(.asciiCapableNumberPad): "asciiNumberPad"
        case .some: "other"
        }
    }

    private static func name(_ value: UIReturnKeyType?) -> String {
        switch value {
        case .none: "unset"
        case .some(.default): "default"
        case .some(.go): "go"
        case .some(.google): "google"
        case .some(.join): "join"
        case .some(.next): "next"
        case .some(.route): "route"
        case .some(.search): "search"
        case .some(.send): "send"
        case .some(.yahoo): "yahoo"
        case .some(.done): "done"
        case .some(.emergencyCall): "emergencyCall"
        case .some(.continue): "continue"
        case .some: "other"
        }
    }

    private static func name(_ value: UITextAutocapitalizationType?) -> String {
        switch value {
        case .none: "unset"
        case .some(.none): "none"
        case .some(.words): "words"
        case .some(.sentences): "sentences"
        case .some(.allCharacters): "allCharacters"
        case .some: "other"
        }
    }

    private static func name(_ value: UITextAutocorrectionType?) -> String {
        switch value {
        case .none: "unset"
        case .some(.default): "default"
        case .some(.no): "no"
        case .some(.yes): "yes"
        case .some: "other"
        }
    }

    private static func name(_ value: UITextSpellCheckingType?) -> String {
        switch value {
        case .none: "unset"
        case .some(.default): "default"
        case .some(.no): "no"
        case .some(.yes): "yes"
        case .some: "other"
        }
    }

    private static func name(_ value: UIKeyboardAppearance?) -> String {
        switch value {
        case .none: "unset"
        case .some(.default): "default"
        case .some(.dark): "dark"
        case .some(.light): "light"
        case .some: "other"
        }
    }
}

/// Whether text the keyboard inserted actually reached the document.
enum InsertionOutcome: String, Sendable {
    /// The document now ends with what we inserted.
    case landed
    /// The document did not change at all. The host dropped the insertion.
    case missing
    /// The document changed, but not into what we sent — the host rewrote it,
    /// reordered it, or put it somewhere else. This is the signature of a host
    /// running its own input pipeline on top of the keyboard.
    case diverged
    /// The host answers no context questions, so nothing can be concluded.
    /// Common without Full Access, and in fields that opt out of context.
    case unverifiable
}

/// Compares the document before and after an insertion.
///
/// Split out from the view controller because the timing around it is awkward
/// enough that the rule itself needs to be checkable without a host app: the
/// proxy is updated asynchronously, so "after" has to be sampled a run-loop
/// turn later, and by then a flaky comparison is indistinguishable from a
/// genuinely broken host.
enum InsertionProbe {
    static func evaluate(
        expected: String,
        before: String?,
        after: String?
    ) -> InsertionOutcome {
        guard let before, let after, !expected.isEmpty else { return .unverifiable }
        // The context is a window, not the whole document, so the host is free
        // to drop characters off the front as it grows. Only the tail is a
        // sound comparison.
        if after.hasSuffix(expected) { return .landed }
        if after == before { return .missing }
        return .diverged
    }
}
