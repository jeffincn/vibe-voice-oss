import Foundation
import VibeVoicePinyin
import VibeVoiceRime

struct RimeSnapshot: Equatable {
    var preedit: String
    var candidates: [RimeCandidate]
    var highlightedIndex: Int
    var pageNumber: Int
    var isLastPage: Bool

    static let empty = RimeSnapshot(
        preedit: "",
        candidates: [],
        highlightedIndex: 0,
        pageNumber: 0,
        isLastPage: true
    )

    var isComposing: Bool { !preedit.isEmpty }
}

final class VibeVoiceRimeEngine {
    private var handle: UnsafeMutableRawPointer?
    private let bufferSize = 16 * 1024

    init?() {
        guard vv_rime_available() != 0,
              let shared = Bundle.main.url(forResource: "RimeData", withExtension: nil) else { return nil }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeVoiceOSS/Rime", isDirectory: true)
        let user = base.appendingPathComponent("User", isDirectory: true)
        let staging = base.appendingPathComponent("Build", isDirectory: true)
        try? FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        handle = shared.path.withCString { sharedPath in
            user.path.withCString { userPath in
                staging.path.withCString { stagingPath in
                    "vibe_pinyin".withCString { schema in
                        vv_rime_create(sharedPath, userPath, stagingPath, schema)
                    }
                }
            }
        }
        guard handle != nil else { return nil }
    }

    deinit { if let handle { vv_rime_destroy(handle) } }

    var isAsciiMode: Bool {
        guard let handle else { return false }
        return "ascii_mode".withCString { vv_rime_get_option(handle, $0) != 0 }
    }

    /// Raw uncommitted code still in librime (used by commitComposition).
    var rawInput: String {
        guard let handle else { return "" }
        var buffer = Array(repeating: CChar(0), count: bufferSize)
        guard vv_rime_get_input(handle, &buffer, bufferSize) != 0 else { return "" }
        return Self.decode(buffer)
    }

    func process(keycode: UInt32, modifiers: UInt32) -> (handled: Bool, commit: String?) {
        guard let handle else { return (false, nil) }
        var commit = Array(repeating: CChar(0), count: bufferSize)
        let handled = vv_rime_process(
            handle, Int32(keycode), Int32(modifiers), &commit, bufferSize
        ) != 0
        return (handled, Self.decode(commit).nilIfEmpty)
    }

    /// Accept a candidate on the current page.
    /// - `.flushed`: librime emitted commit text — insert it into the document.
    /// - `.inline`: selection stayed in the preedit (partial phrase).
    /// - `nil`: librime rejected the index.
    enum SelectOutcome: Equatable {
        case flushed(String)
        case inline
    }

    func selectCandidate(_ index: Int) -> SelectOutcome? {
        guard let handle else { return nil }
        var commit = Array(repeating: CChar(0), count: bufferSize)
        guard vv_rime_select_candidate(handle, numericCast(index), &commit, bufferSize) != 0 else {
            return nil
        }
        if let text = Self.decode(commit).nilIfEmpty {
            return .flushed(text)
        }
        return .inline
    }

    func commitComposition() -> String? {
        guard let handle else { return nil }
        var commit = Array(repeating: CChar(0), count: bufferSize)
        guard vv_rime_commit_composition(handle, &commit, bufferSize) != 0 else { return nil }
        return Self.decode(commit).nilIfEmpty
    }

    func snapshot() -> RimeSnapshot {
        guard let handle else { return .empty }
        var preedit = Array(repeating: CChar(0), count: bufferSize)
        var rawCandidates = Array(repeating: CChar(0), count: bufferSize)
        var highlighted: Int32 = 0
        var pageNumber: Int32 = 0
        var isLastPage: Int32 = 1
        guard vv_rime_snapshot(
            handle,
            &preedit, bufferSize,
            &rawCandidates, bufferSize,
            &highlighted, &pageNumber, &isLastPage
        ) != 0 else {
            return .empty
        }
        let candidates = Self.decode(rawCandidates)
            .split(separator: "\u{1f}")
            .enumerated()
            .map { index, record -> RimeCandidate in
                let fields = record.split(separator: "\u{1e}", maxSplits: 1, omittingEmptySubsequences: false)
                return RimeCandidate(
                    text: String(fields[0]),
                    comment: fields.count > 1 && !fields[1].isEmpty ? String(fields[1]) : nil,
                    engineIndex: index
                )
            }
        return RimeSnapshot(
            preedit: Self.decode(preedit),
            candidates: candidates,
            highlightedIndex: candidates.indices.contains(Int(highlighted)) ? Int(highlighted) : 0,
            pageNumber: Int(pageNumber),
            isLastPage: isLastPage != 0
        )
    }

    func clear() { if let handle { vv_rime_clear(handle) } }

    /// Read-only dictionary probe on this session. Clears composition before and
    /// after so a shadow session can resolve corrected pinyin without touching
    /// the user's main composition.
    func lookupCandidates(forPinyin code: String) -> [RimeCandidate] {
        let letters = code.lowercased().filter { $0.isASCII && $0.isLetter }
        guard !letters.isEmpty else { return [] }
        clear()
        for character in letters {
            guard let value = character.unicodeScalars.first?.value else { continue }
            _ = process(keycode: value, modifiers: 0)
        }
        let candidates = snapshot().candidates
        clear()
        return candidates
    }

    private static func decode(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
