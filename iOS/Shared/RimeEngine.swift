import Foundation

struct RimeCandidate: Equatable, Sendable {
    let text: String
    let comment: String?
}

struct RimeSnapshot: Equatable, Sendable {
    var preedit: String
    var candidates: [RimeCandidate]
    var highlightedIndex: Int

    static let empty = RimeSnapshot(preedit: "", candidates: [], highlightedIndex: 0)
}

protocol RimeEngine: AnyObject {
    var snapshot: RimeSnapshot { get }

    @discardableResult
    func process(letter: Character) -> RimeSnapshot
    @discardableResult
    func backspace() -> RimeSnapshot
    func selectCandidate(at index: Int) -> String?
    func commitBestCandidate() -> String?
    func reset()
}

/// Phase-one deterministic engine used to build and test the keyboard lifecycle.
/// It is intentionally isolated behind `RimeEngine`; the production factory will
/// replace it with the BSD-licensed librime C API without changing keyboard UI.
final class PrototypeRimeEngine: RimeEngine {
    private static let lexicon: [String: [String]] = [
        "ni": ["你", "呢", "尼", "泥", "拟"],
        "hao": ["好", "号", "浩", "豪", "毫"],
        "nihao": ["你好", "拟好"],
        "wo": ["我", "握", "窝", "卧"],
        "shi": ["是", "时", "事", "市", "十"],
        "zhong": ["中", "种", "重", "众"],
        "guo": ["国", "过", "果", "锅"],
        "zhongguo": ["中国"],
        "shuru": ["输入"],
        "shurufa": ["输入法"],
    ]

    private var composition = ""

    var snapshot: RimeSnapshot {
        guard !composition.isEmpty else { return .empty }
        let words = Self.lexicon[composition] ?? [composition]
        return RimeSnapshot(
            preedit: composition,
            candidates: words.map { RimeCandidate(text: $0, comment: nil) },
            highlightedIndex: 0
        )
    }

    @discardableResult
    func process(letter: Character) -> RimeSnapshot {
        guard letter.isASCII, letter.isLetter || letter == "'" else { return snapshot }
        composition.append(Character(letter.lowercased()))
        return snapshot
    }

    @discardableResult
    func backspace() -> RimeSnapshot {
        if !composition.isEmpty {
            composition.removeLast()
        }
        return snapshot
    }

    func selectCandidate(at index: Int) -> String? {
        let current = snapshot
        guard current.candidates.indices.contains(index) else { return nil }
        let text = current.candidates[index].text
        reset()
        return text
    }

    func commitBestCandidate() -> String? {
        selectCandidate(at: snapshot.highlightedIndex)
    }

    func reset() {
        composition = ""
    }
}
