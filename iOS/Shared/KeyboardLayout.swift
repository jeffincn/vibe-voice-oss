import Foundation

// This is the keyboard extension's layout, but it lives in Shared because it is
// a pure value model with no UIKit in it and the unit test target can only see
// sources compiled into the containing app.

/// Which set of keys the character rows are currently showing.
enum KeyboardPlane: Equatable {
    case letters
    case numbers
    case symbols

    /// The plane the leftmost key of the bottom row switches to.
    var alternate: KeyboardPlane {
        self == .letters ? .numbers : .letters
    }

    var alternateLabel: String {
        self == .letters ? "123" : "ABC"
    }
}

/// A key in one of the three character rows. The utility row is built directly
/// by the view controller so it can match system Mandarin proportions
/// (123 / emoji / space / return) without crowding language chrome into the grid.
enum KeyboardKey: Equatable {
    /// Text the key produces. Letters go to librime; punctuation is mapped by
    /// `ChinesePunctuation` and inserted directly so it never sits in preedit.
    case character(String)
    case shift
    case plane(KeyboardPlane)
    case backspace
}

/// Full-width forms for Chinese mode, kept in sync with `vibe_pinyin.schema.yaml`
/// `punctuator.half_shape`. The keyboard applies these itself instead of feeding
/// punctuation into librime — otherwise symbols linger in the composition bar.
enum ChinesePunctuation {
    static func mapped(_ character: Character) -> String {
        switch character {
        case "'": return "‘"
        case "\"": return "“"
        case ",": return "，"
        case ".": return "。"
        case "!": return "！"
        case "?": return "？"
        case ":": return "："
        case ";": return "；"
        case "(": return "（"
        case ")": return "）"
        case "<": return "《"
        case ">": return "》"
        case "[": return "【"
        case "]": return "】"
        case "\\": return "、"
        case "^": return "……"
        case "_": return "——"
        case "~": return "～"
        case "`": return "·"
        case "$", "¥": return "￥"
        default: return String(character)
        }
    }
}

enum KeyboardShift: Equatable {
    case off
    /// Applies to the next character only.
    case on
    /// Stays until tapped again.
    case locked

    var isRaised: Bool { self != .off }
}

extension KeyboardPlane {
    /// The three character rows, top to bottom. The bottom row of each plane
    /// keeps backspace on the right the way the system keyboard does.
    var rows: [[KeyboardKey]] {
        switch self {
        case .letters:
            return [
                Self.keys("qwertyuiop"),
                Self.keys("asdfghjkl"),
                [.shift] + Self.keys("zxcvbnm") + [.backspace],
            ]
        case .numbers:
            return [
                Self.keys("1234567890"),
                Self.keys("-/:;()") + Self.keys("¥&@\""),
                [.plane(.symbols)] + Self.keys(".,?!'") + [.backspace],
            ]
        case .symbols:
            return [
                Self.keys("[]{}#%^*+="),
                Self.keys("_\\|~<>") + Self.keys("€£¥·"),
                [.plane(.numbers)] + Self.keys(".,?!'") + [.backspace],
            ]
        }
    }

    /// True for the row that sits half a key in from both edges.
    func isInset(row index: Int) -> Bool {
        self == .letters && index == 1
    }

    private static func keys(_ characters: String) -> [KeyboardKey] {
        characters.map { .character(String($0)) }
    }
}
