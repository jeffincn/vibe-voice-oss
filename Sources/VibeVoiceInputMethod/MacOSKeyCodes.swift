import AppKit
import Carbon

/// macOS keycode / modifier → librime (X11 keysym + IBus masks).
/// Ported from Squirrel's `MacOSKeyCodes.swift`:
/// https://github.com/rime/squirrel/blob/master/sources/MacOSKeyCodes.swift
enum RimeKeycode {
    // MARK: - IBus / librime modifier masks (rime/key_table.h)

    static let shiftMask: UInt32 = 1 << 0
    static let lockMask: UInt32 = 1 << 1
    static let controlMask: UInt32 = 1 << 2
    static let altMask: UInt32 = 1 << 3
    static let superMask: UInt32 = 1 << 26
    static let releaseMask: UInt32 = 1 << 30

    // MARK: - X11 keysyms used by librime process_key

    private enum XK {
        static let voidSymbol: Int32 = 0xffffff
        static let backSpace: Int32 = 0xff08
        static let tab: Int32 = 0xff09
        static let `return`: Int32 = 0xff0d
        static let escape: Int32 = 0xff1b
        static let delete: Int32 = 0xffff
        static let help: Int32 = 0xff6a
        static let home: Int32 = 0xff50
        static let left: Int32 = 0xff51
        static let up: Int32 = 0xff52
        static let right: Int32 = 0xff53
        static let down: Int32 = 0xff54
        static let pageUp: Int32 = 0xff55
        static let pageDown: Int32 = 0xff56
        static let end: Int32 = 0xff57
        static let capsLock: Int32 = 0xffe5
        static let shiftL: Int32 = 0xffe1
        static let shiftR: Int32 = 0xffe2
        static let controlL: Int32 = 0xffe3
        static let controlR: Int32 = 0xffe4
        static let altL: Int32 = 0xffe9
        static let altR: Int32 = 0xffea
        static let superL: Int32 = 0xffeb
        static let superR: Int32 = 0xffec
        static let hyperL: Int32 = 0xffed
        static let space: Int32 = 0x0020
        static let clear: Int32 = 0xff0b
        static let section: Int32 = 0x00a7
        static let yen: Int32 = 0x00a5
        static let underscore: Int32 = 0x005f
        static let comma: Int32 = 0x002c
        static let eisuShift: Int32 = 0xff2f
        static let kanaShift: Int32 = 0xff2e
        static let f1: Int32 = 0xffbe
        static let f2: Int32 = 0xffbf
        static let f3: Int32 = 0xffc0
        static let f4: Int32 = 0xffc1
        static let f5: Int32 = 0xffc2
        static let f6: Int32 = 0xffc3
        static let f7: Int32 = 0xffc4
        static let f8: Int32 = 0xffc5
        static let f9: Int32 = 0xffc6
        static let f10: Int32 = 0xffc7
        static let f11: Int32 = 0xffc8
        static let f12: Int32 = 0xffc9
        static let f13: Int32 = 0xffca
        static let f14: Int32 = 0xffcb
        static let f15: Int32 = 0xffcc
        static let f16: Int32 = 0xffcd
        static let f17: Int32 = 0xffce
        static let f18: Int32 = 0xffcf
        static let f19: Int32 = 0xffd0
        static let f20: Int32 = 0xffd1
        static let kp0: Int32 = 0xffb0
        static let kp1: Int32 = 0xffb1
        static let kp2: Int32 = 0xffb2
        static let kp3: Int32 = 0xffb3
        static let kp4: Int32 = 0xffb4
        static let kp5: Int32 = 0xffb5
        static let kp6: Int32 = 0xffb6
        static let kp7: Int32 = 0xffb7
        static let kp8: Int32 = 0xffb8
        static let kp9: Int32 = 0xffb9
        static let kpDecimal: Int32 = 0xffae
        static let kpEqual: Int32 = 0xffbd
        static let kpSubtract: Int32 = 0xffad
        static let kpMultiply: Int32 = 0xffaa
        static let kpAdd: Int32 = 0xffab
        static let kpDivide: Int32 = 0xffaf
        static let kpEnter: Int32 = 0xff8d
        static let bracketleft: Int32 = 0x005b
        static let bracketright: Int32 = 0x005d
        static let backslash: Int32 = 0x005c
        static let minus: Int32 = 0x002d
    }

    static func osxModifiersToRime(modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var ret: UInt32 = 0
        if modifiers.contains(.capsLock) { ret |= lockMask }
        if modifiers.contains(.shift) { ret |= shiftMask }
        if modifiers.contains(.control) { ret |= controlMask }
        if modifiers.contains(.option) { ret |= altMask }
        if modifiers.contains(.command) { ret |= superMask }
        return ret
    }

    static func osxKeycodeToRime(keycode: UInt16, keychar: Character?, shift: Bool, caps: Bool) -> UInt32 {
        if let code = keycodeMappings[Int(keycode)] {
            return UInt32(code)
        }

        if let keychar, keychar.isASCII, let codeValue = keychar.unicodeScalars.first?.value {
            // IBus/Rime use different keycodes for uppercase and lowercase letters.
            if keychar.isLowercase && (shift != caps) {
                return keychar.uppercased().unicodeScalars.first!.value
            }
            switch codeValue {
            case 0x20...0x7e:
                return codeValue
            case 0x1b:
                return UInt32(XK.bracketleft)
            case 0x1c:
                return UInt32(XK.backslash)
            case 0x1d:
                return UInt32(XK.bracketright)
            case 0x1f:
                return UInt32(XK.minus)
            default:
                break
            }
        }

        if let code = additionalCodeMappings[Int(keycode)] {
            return UInt32(code)
        }
        return UInt32(XK.voidSymbol)
    }

    static let modifierKeycodes: Set<UInt16> = [
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_CapsLock),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
        UInt16(kVK_Function),
    ]

    static func inferModifierKeycode(from changes: NSEvent.ModifierFlags) -> UInt16? {
        if changes.contains(.capsLock) { return UInt16(kVK_CapsLock) }
        if changes.contains(.shift) { return UInt16(kVK_Shift) }
        if changes.contains(.control) { return UInt16(kVK_Control) }
        if changes.contains(.option) { return UInt16(kVK_Option) }
        if changes.contains(.command) { return UInt16(kVK_Command) }
        return nil
    }

    private static let keycodeMappings: [Int: Int32] = [
        kVK_CapsLock: XK.capsLock,
        kVK_Command: XK.superL,
        kVK_RightCommand: XK.superR,
        kVK_Control: XK.controlL,
        kVK_RightControl: XK.controlR,
        kVK_Function: XK.hyperL,
        kVK_Option: XK.altL,
        kVK_RightOption: XK.altR,
        kVK_Shift: XK.shiftL,
        kVK_RightShift: XK.shiftR,

        kVK_Delete: XK.backSpace,
        kVK_Escape: XK.escape,
        kVK_ForwardDelete: XK.delete,
        kVK_Help: XK.help,
        kVK_Return: XK.return,
        kVK_Space: XK.space,
        kVK_Tab: XK.tab,

        kVK_F1: XK.f1, kVK_F2: XK.f2, kVK_F3: XK.f3, kVK_F4: XK.f4,
        kVK_F5: XK.f5, kVK_F6: XK.f6, kVK_F7: XK.f7, kVK_F8: XK.f8,
        kVK_F9: XK.f9, kVK_F10: XK.f10, kVK_F11: XK.f11, kVK_F12: XK.f12,
        kVK_F13: XK.f13, kVK_F14: XK.f14, kVK_F15: XK.f15, kVK_F16: XK.f16,
        kVK_F17: XK.f17, kVK_F18: XK.f18, kVK_F19: XK.f19, kVK_F20: XK.f20,

        kVK_UpArrow: XK.up,
        kVK_DownArrow: XK.down,
        kVK_LeftArrow: XK.left,
        kVK_RightArrow: XK.right,
        kVK_PageUp: XK.pageUp,
        kVK_PageDown: XK.pageDown,
        kVK_Home: XK.home,
        kVK_End: XK.end,

        kVK_ANSI_Keypad0: XK.kp0, kVK_ANSI_Keypad1: XK.kp1,
        kVK_ANSI_Keypad2: XK.kp2, kVK_ANSI_Keypad3: XK.kp3,
        kVK_ANSI_Keypad4: XK.kp4, kVK_ANSI_Keypad5: XK.kp5,
        kVK_ANSI_Keypad6: XK.kp6, kVK_ANSI_Keypad7: XK.kp7,
        kVK_ANSI_Keypad8: XK.kp8, kVK_ANSI_Keypad9: XK.kp9,
        kVK_ANSI_KeypadClear: XK.clear,
        kVK_ANSI_KeypadDecimal: XK.kpDecimal,
        kVK_ANSI_KeypadEquals: XK.kpEqual,
        kVK_ANSI_KeypadMinus: XK.kpSubtract,
        kVK_ANSI_KeypadMultiply: XK.kpMultiply,
        kVK_ANSI_KeypadPlus: XK.kpAdd,
        kVK_ANSI_KeypadDivide: XK.kpDivide,
        kVK_ANSI_KeypadEnter: XK.kpEnter,

        kVK_ISO_Section: XK.section,
        kVK_JIS_Yen: XK.yen,
        kVK_JIS_Underscore: XK.underscore,
        kVK_JIS_KeypadComma: XK.comma,
        kVK_JIS_Eisu: XK.eisuShift,
        kVK_JIS_Kana: XK.kanaShift,
    ]

    private static let additionalCodeMappings: [Int: Int32] = [
        kVK_ANSI_0: 0x0030, kVK_ANSI_1: 0x0031, kVK_ANSI_2: 0x0032,
        kVK_ANSI_3: 0x0033, kVK_ANSI_4: 0x0034, kVK_ANSI_5: 0x0035,
        kVK_ANSI_6: 0x0036, kVK_ANSI_7: 0x0037, kVK_ANSI_8: 0x0038,
        kVK_ANSI_9: 0x0039,
        kVK_ANSI_RightBracket: 0x005d,
        kVK_ANSI_LeftBracket: 0x005b,
        kVK_ANSI_Comma: 0x002c,
        kVK_ANSI_Grave: 0x0060,
        kVK_ANSI_Period: 0x002e,
        kVK_ANSI_Semicolon: 0x003b,
        kVK_ANSI_Quote: 0x0027,
        kVK_ANSI_Backslash: 0x005c,
        kVK_ANSI_Minus: 0x002d,
        kVK_ANSI_Slash: 0x002f,
        kVK_ANSI_Equal: 0x003d,
        kVK_ANSI_A: 0x0061, kVK_ANSI_B: 0x0062, kVK_ANSI_C: 0x0063,
        kVK_ANSI_D: 0x0064, kVK_ANSI_E: 0x0065, kVK_ANSI_F: 0x0066,
        kVK_ANSI_G: 0x0067, kVK_ANSI_H: 0x0068, kVK_ANSI_I: 0x0069,
        kVK_ANSI_J: 0x006a, kVK_ANSI_K: 0x006b, kVK_ANSI_L: 0x006c,
        kVK_ANSI_M: 0x006d, kVK_ANSI_N: 0x006e, kVK_ANSI_O: 0x006f,
        kVK_ANSI_P: 0x0070, kVK_ANSI_Q: 0x0071, kVK_ANSI_R: 0x0072,
        kVK_ANSI_S: 0x0073, kVK_ANSI_T: 0x0074, kVK_ANSI_U: 0x0075,
        kVK_ANSI_V: 0x0076, kVK_ANSI_W: 0x0077, kVK_ANSI_X: 0x0078,
        kVK_ANSI_Y: 0x0079, kVK_ANSI_Z: 0x007a,
    ]
}
