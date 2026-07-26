import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum TextInsertionMethod: Sendable {
    case accessibility
    case pasteboard
    case appleScript
}

enum PasteService {
    @MainActor
    static func requestAccessibilityIfNeeded(prompt: Bool = true) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    @MainActor
    static func insert(_ text: String, into processIdentifier: pid_t?) async throws -> TextInsertionMethod {
        guard AXIsProcessTrusted() else {
            throw PasteError.accessibilityDenied
        }

        if let processIdentifier,
           let application = NSRunningApplication(processIdentifier: processIdentifier) {
            let isWebEditor = prefersPasteboardInsertion(application)
            application.activate()
            let activationDelay: Duration = isWebEditor ? .milliseconds(420) : .milliseconds(150)
            try? await Task.sleep(for: activationDelay)

            if isWebEditor {
                return try await insertIntoPasteboardTarget(text)
            }

            if insertUsingAccessibility(text, processIdentifier: processIdentifier) {
                return .accessibility
            }
        }

        return try await insertIntoPasteboardTarget(text)
    }

    /// Try CGEvent Cmd+V first; fall back to AppleScript System Events keystroke.
    @MainActor
    private static func insertIntoPasteboardTarget(_ text: String) async throws -> TextInsertionMethod {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        // Clipboard managers watch the general pasteboard. The transient marker asks
        // them not to archive a transcript the user never chose to copy.
        pasteboard.setData(Data(), forType: .transientMarker)
        pasteboard.setString(text, forType: .string)

        // CGEvent.post returns nothing and is silently dropped when the process
        // lacks post-event access, so this path used to report success on a paste
        // that never happened. Ask first, and go straight to AppleScript if not.
        if CGPreflightPostEventAccess(), let method = try? await postCmdV() {
            try? await Task.sleep(for: .milliseconds(800))
            restoreIfUnchanged(snapshot: snapshot, expected: text)
            return method
        }

        if let method = try? await appleScriptCmdV() {
            try? await Task.sleep(for: .milliseconds(800))
            restoreIfUnchanged(snapshot: snapshot, expected: text)
            return method
        }

        throw PasteError.cannotCreateEvent
    }

    /// Simulate Cmd+V via CGEvent.
    @MainActor
    private static func postCmdV() async throws -> TextInsertionMethod {
        let key = virtualKey(for: "v") ?? Self.usKeyCodeV
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw PasteError.cannotCreateEvent
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return .pasteboard
    }

    /// 'V' on the standard US layout, used only when the active layout cannot be read.
    private static let usKeyCodeV: CGKeyCode = 9

    /// The virtual key that produces `character` on the layout currently in use.
    ///
    /// Hard-coding the US position sends whatever letter sits there on Dvorak,
    /// AZERTY or Colemak, so the paste shortcut fires some unrelated command.
    /// The scan is 128 table lookups, cheap enough to redo per paste rather than
    /// cache and risk going stale when the user switches layout.
    @MainActor
    private static func virtualKey(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())

        return layoutData.withUnsafeBytes { buffer -> CGKeyCode? in
            guard let layout = buffer.baseAddress?
                .assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var characters = [UniChar](repeating: 0, count: 4)
            for code in 0..<CGKeyCode(128) {
                var deadKeyState: UInt32 = 0
                var length = 0
                let status = UCKeyTranslate(
                    layout,
                    UInt16(code),
                    UInt16(kUCKeyActionDown),
                    0,
                    keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
                guard status == noErr, length == 1,
                      let scalar = UnicodeScalar(characters[0]) else { continue }
                if Character(scalar) == character {
                    return code
                }
            }
            return nil
        }
    }

    /// Simulate Cmd+V via AppleScript System Events — survives stricter
    /// macOS 26 CGEvent restrictions that block direct event posting.
    @MainActor
    private static func appleScriptCmdV() async throws -> TextInsertionMethod {
        let script = NSAppleScript(source: """
            tell application "System Events"
                keystroke "v" using command down
            end tell
        """)
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            throw PasteError.cannotCreateEvent
        }
        return .appleScript
    }

    /// Editors that accept `kAXSelectedText` and then quietly discard it, so only a
    /// simulated paste actually lands.
    private static let pasteboardOnlyBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.openai.chat",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "company.thebrowser.Browser", // Arc
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
    ]

    private static let pasteboardOnlyNameWords: Set<String> = [
        "cursor", "codex", "chatgpt", "electron", "code", "chrome", "chromium",
        "arc", "slack", "discord",
    ]

    private static func prefersPasteboardInsertion(_ application: NSRunningApplication) -> Bool {
        if let bundleID = application.bundleIdentifier,
           pasteboardOnlyBundleIDs.contains(bundleID) {
            return true
        }
        // Names are matched whole-word. Substring matching treated "Search" as Arc
        // and "Xcode" as Codex, forcing a slow clipboard paste on unrelated apps.
        let words = (application.localizedName ?? "")
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        return !Set(words).isDisjoint(with: pasteboardOnlyNameWords)
    }

    @MainActor
    private static func insertUsingAccessibility(_ text: String, processIdentifier: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(processIdentifier)
        var focusedValue: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        // Some apps answer the focus query with a string or a dictionary. Casting
        // that to AXUIElement unchecked is undefined behaviour, and the crash lands
        // on whatever the user happened to be typing into.
        guard focusStatus == .success, let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return false
        }

        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        let insertStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return insertStatus == .success
    }

    private static func restoreIfUnchanged(snapshot: PasteboardSnapshot, expected: String) {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == expected {
            snapshot.restore(to: pasteboard)
        }
    }
}

private extension NSPasteboard.PasteboardType {
    /// Convention honoured by clipboard managers (Maccy, Alfred, Paste, Raycast).
    static let transientMarker = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restoredItems = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

enum PasteError: LocalizedError {
    case accessibilityDenied
    case cannotCreateEvent

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied: L10n.t(.errAccessibilityDenied)
        case .cannotCreateEvent: L10n.t(.errCannotCreateEvent)
        }
    }
}
