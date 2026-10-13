import AppKit

/// Menu-bar apps (`LSUIElement`) stay out of Dock / ⌘⇥ by default.
/// Promote to `.regular` while Settings or report windows are open so the user
/// can switch back with Command-Tab; demote when those windows are gone.
@MainActor
enum AppActivation {
    static func promoteForUserWindows() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func demoteIfNoUserWindows() {
        // Defer so the closing window is already off the list.
        DispatchQueue.main.async {
            guard !hasVisibleUserWindow() else { return }
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    static func refreshFromOpenWindows() {
        if hasVisibleUserWindow() {
            promoteForUserWindows()
        } else {
            demoteIfNoUserWindows()
        }
    }

    /// Settings + Stage Timing + Token Usage: normal titled windows.
    /// Excludes MenuBarExtra, Recording HUD, and Result Banner panels.
    static func hasVisibleUserWindow() -> Bool {
        NSApp.windows.contains { isUserSwitcherWindow($0) }
    }

    static func isUserSwitcherWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, !window.isSheet else { return false }
        // HUD / banner / menu-bar panels sit above `.normal` or are nonactivating.
        guard window.level == .normal else { return false }
        if window.styleMask.contains(.nonactivatingPanel) { return false }
        // Require a real titled window the user can close / miniaturize.
        guard window.styleMask.contains(.titled) else { return false }
        return window.canBecomeKey || window.canBecomeMain
    }
}
