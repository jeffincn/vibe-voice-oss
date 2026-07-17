import AppKit
import ApplicationServices

enum TextInsertionMethod: Sendable {
    case accessibility
    case pasteboard
}

enum PasteService {
    @MainActor
    static func requestAccessibilityIfNeeded() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Inserts text into the application that owned the cursor when recording began.
    /// AX selected-text insertion is clipboard-free; Cmd+V is the compatibility fallback.
    @MainActor
    static func insert(_ text: String, into processIdentifier: pid_t?) async throws -> TextInsertionMethod {
        guard AXIsProcessTrusted() else {
            _ = requestAccessibilityIfNeeded()
            throw PasteError.accessibilityDenied
        }

        if let processIdentifier,
           let application = NSRunningApplication(processIdentifier: processIdentifier) {
            application.activate()
            try? await Task.sleep(for: .milliseconds(150))

            // Chromium/Electron editors may report AXSelectedText writes as successful
            // without updating their internal editor model. A real paste event is reliable there.
            if prefersPasteboardInsertion(application) {
                try await insertUsingPasteboard(text)
                return .pasteboard
            }

            if insertUsingAccessibility(text, processIdentifier: processIdentifier) {
                return .accessibility
            }
        }

        try await insertUsingPasteboard(text)
        return .pasteboard
    }

    private static func prefersPasteboardInsertion(_ application: NSRunningApplication) -> Bool {
        let identity = [application.bundleIdentifier, application.localizedName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let webEditorMarkers = [
            "cursor", "codex", "chatgpt", "electron", "visual studio code",
            "chrome", "chromium", "arc", "slack", "discord"
        ]
        return webEditorMarkers.contains { identity.contains($0) }
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
        guard focusStatus == .success, let focusedValue else { return false }

        let focusedElement = unsafeDowncast(focusedValue, to: AXUIElement.self)
        let insertStatus = AXUIElementSetAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return insertStatus == .success
    }

    @MainActor
    private static func insertUsingPasteboard(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw PasteError.cannotCreateEvent
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(800))
        if pasteboard.string(forType: .string) == text {
            snapshot.restore(to: pasteboard)
        }
    }
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
        case .accessibilityDenied: "需要辅助功能权限才能向当前光标插入文字。"
        case .cannotCreateEvent: "无法生成文本输入事件。"
        }
    }
}
