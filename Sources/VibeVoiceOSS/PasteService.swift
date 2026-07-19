import AppKit
import ApplicationServices

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
        pasteboard.setString(text, forType: .string)

        if let method = try? await postCmdV() {
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
        // virtualKey 9 = 'V' on the standard US keyboard layout.
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw PasteError.cannotCreateEvent
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        return .pasteboard
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

    private static func restoreIfUnchanged(snapshot: PasteboardSnapshot, expected: String) {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) == expected {
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
        case .accessibilityDenied: "需要辅助功能权限才能向当前光标插入文字。请在系统设置 → 隐私与安全 → 辅助功能中关闭再重新打开 Vibe Voice OSS 的开关。"
        case .cannotCreateEvent: "无法生成文本输入事件。"
        }
    }
}
