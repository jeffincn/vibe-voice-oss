import Foundation

/// Merges Streaming ASR partials into stable + unstable display text, then locks on final.
struct TranscriptAccumulator: Equatable, Sendable {
    private(set) var stablePrefix: String = ""
    private(set) var unstableSuffix: String = ""
    private(set) var isFinalized: Bool = false
    private(set) var finalText: String?
    /// True when the last `final` disagreed with the prior stable prefix.
    private(set) var divergedFromStable: Bool = false

    var displayText: String {
        if let finalText { return finalText }
        if stablePrefix.isEmpty { return unstableSuffix }
        if unstableSuffix.isEmpty { return stablePrefix }
        // Avoid double spaces when joining committed + live tails.
        if stablePrefix.hasSuffix(" ") || unstableSuffix.hasPrefix(" ")
            || stablePrefix.hasSuffix("\n") || unstableSuffix.hasPrefix("\n") {
            return stablePrefix + unstableSuffix
        }
        // CJK: usually no space; ASCII letters/digits: insert a space between clauses.
        let last = stablePrefix.unicodeScalars.last
        let first = unstableSuffix.unicodeScalars.first
        let needSpace: Bool = {
            guard let last, let first else { return false }
            return Self.isASCIIAlphaNum(last) && Self.isASCIIAlphaNum(first)
        }()
        return needSpace ? stablePrefix + " " + unstableSuffix : stablePrefix + unstableSuffix
    }

    var hasContent: Bool { !displayText.isEmpty }

    mutating func reset() {
        stablePrefix = ""
        unstableSuffix = ""
        isFinalized = false
        finalText = nil
        divergedFromStable = false
    }

    private static func isASCIIAlphaNum(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value) // 0-9
            || (65...90).contains(scalar.value) // A-Z
            || (97...122).contains(scalar.value) // a-z
    }

    /// Update the live (revisable) tail. Prefers smooth growth over full flicker when possible.
    mutating func applyPartial(_ text: String) {
        guard !isFinalized else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            unstableSuffix = ""
            return
        }

        // Soft growth: new hypothesis extends the previous live tail.
        if !unstableSuffix.isEmpty, trimmed.hasPrefix(unstableSuffix) {
            unstableSuffix = trimmed
            return
        }
        // Soft growth against full display (model returned cumulative text).
        let previous = displayText
        if !previous.isEmpty, trimmed.hasPrefix(previous) {
            if stablePrefix.isEmpty {
                unstableSuffix = trimmed
            } else if trimmed.hasPrefix(stablePrefix) {
                unstableSuffix = String(trimmed.dropFirst(stablePrefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let rest = String(trimmed.dropFirst(previous.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                unstableSuffix = rest.isEmpty ? trimmed : rest
            }
            return
        }

        unstableSuffix = trimmed
    }

    /// Append confirmed text that must not roll back.
    mutating func applyStable(_ text: String) {
        guard !isFinalized else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if stablePrefix.isEmpty {
            stablePrefix = trimmed
        } else if trimmed.hasPrefix(stablePrefix) {
            stablePrefix = trimmed
        } else {
            let needsSpace: Bool = {
                guard let last = stablePrefix.unicodeScalars.last,
                      let first = trimmed.unicodeScalars.first else { return false }
                return Self.isASCIIAlphaNum(last) && Self.isASCIIAlphaNum(first)
            }()
            stablePrefix += needsSpace ? " " + trimmed : trimmed
        }
        // Drop live tail that was absorbed into the new stable region.
        if !unstableSuffix.isEmpty {
            if trimmed.hasPrefix(unstableSuffix) || unstableSuffix.hasPrefix(trimmed)
                || displayText.hasPrefix(stablePrefix) {
                // Re-recognize live region separately; clear stale overlapping tail.
                if unstableSuffix.hasPrefix(trimmed) {
                    unstableSuffix = String(unstableSuffix.dropFirst(trimmed.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                } else if stablePrefix.contains(unstableSuffix) {
                    unstableSuffix = ""
                } else {
                    // Keep live tail; commit was only the older segment.
                }
            }
        }
    }

    /// After a stable commit of a segment, replace live tail with a fresh window hypothesis.
    mutating func replaceLiveTail(_ text: String) {
        guard !isFinalized else { return }
        unstableSuffix = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lock the transcript. Final text always wins over interim display.
    @discardableResult
    mutating func applyFinal(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stablePrefix.isEmpty, !trimmed.isEmpty, !trimmed.hasPrefix(stablePrefix) {
            divergedFromStable = true
        }
        finalText = trimmed
        stablePrefix = trimmed
        unstableSuffix = ""
        isFinalized = true
        return trimmed
    }
}
