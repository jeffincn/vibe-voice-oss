import Foundation

/// Reconcile a composed reasoning line with the live Rime page so high-frequency
/// single characters (帮 ≫ 棒) cannot outrank a full phrase Rime already knows.
public enum ReasoningRimeReconciler {
    public struct Outcome: Equatable, Sendable {
        public let text: String
        /// True when we replaced the composer output with a better Rime peer.
        public let usedRimePeer: Bool
    }

    /// Prefer a same-length Rime peer that only differs in the last character
    /// (魔法帮 → 魔法棒), or a slightly longer Rime phrase that extends the composition.
    public static func reconcile(
        composed: String,
        rimeCandidates: [RimeCandidate]
    ) -> Outcome {
        let composed = composed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard composed.count >= 2 else {
            return Outcome(text: composed, usedRimePeer: false)
        }

        let rimeTexts = rimeCandidates.compactMap { candidate -> String? in
            // Only trust engine rows, not our own previous synthetics.
            if candidate.source == ReasoningCandidate.source
                || candidate.source == PinyinTypoCorrector.typoFixSource {
                return nil
            }
            let text = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        if rimeTexts.contains(composed) {
            return Outcome(text: composed, usedRimePeer: false)
        }

        // Same length, identical except the last character — trust Rime.
        if let peer = rimeTexts.first(where: { peer in
            peer.count == composed.count
                && peer.count >= 2
                && peer.dropLast() == composed.dropLast()
                && peer != composed
        }) {
            return Outcome(text: peer, usedRimePeer: true)
        }

        // Share a long prefix (≥2) and only differ near the end (edit distance-ish).
        if composed.count >= 3,
           let peer = rimeTexts.prefix(8).first(where: { peer in
               peer.count == composed.count
                   && commonPrefixLength(peer, composed) >= composed.count - 1
                   && peer != composed
           }) {
            return Outcome(text: peer, usedRimePeer: true)
        }

        // Rime already has a longer full phrase starting with our composition
        // (e.g. composed "魔法" while page has "魔法棒").
        if let longer = rimeTexts.first(where: { peer in
            peer.hasPrefix(composed)
                && peer.count > composed.count
                && peer.count <= composed.count + 2
        }) {
            return Outcome(text: longer, usedRimePeer: true)
        }

        return Outcome(text: composed, usedRimePeer: false)
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        for (left, right) in zip(a, b) {
            guard left == right else { break }
            count += 1
        }
        return count
    }
}
