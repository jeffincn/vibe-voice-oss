import AppKit
import Carbon
import InputMethodKit

private enum InputSourceCommand: String {
    case register = "--register-input-source"
    case enable = "--enable-input-source"
    case select = "--select-input-source"
}

private func inputSourceID(_ source: TISInputSource) -> String? {
    guard let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
}

private func inputSourceBoolean(_ source: TISInputSource, _ key: CFString) -> Bool {
    guard let property = TISGetInputSourceProperty(source, key) else {
        return false
    }
    return CFBooleanGetValue(
        Unmanaged<CFBoolean>.fromOpaque(property).takeUnretainedValue()
    )
}

private func installedInputSources() -> [TISInputSource] {
    (TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
}

/// Text Input Sources rebuilds its cache asynchronously after registration, so
/// a mode looked up immediately by the installer is often not there yet.
private func awaitInputSource(_ modeID: String) -> TISInputSource? {
    for attempt in 0..<10 {
        if let source = installedInputSources().first(where: { inputSourceID($0) == modeID }) {
            return source
        }
        if attempt < 9 { Thread.sleep(forTimeInterval: 0.3) }
    }
    return nil
}

private func runInputSourceCommand(_ command: InputSourceCommand) -> Int32 {
    guard let bundleID = Bundle.main.bundleIdentifier else {
        fputs("error: missing input method bundle identifier\n", stderr)
        return 1
    }
    let modeID = "\(bundleID).Hans"

    switch command {
    case .register:
        let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        if status != noErr {
            fputs("error: TISRegisterInputSource failed with status \(status)\n", stderr)
            return 1
        }
    case .enable:
        guard let source = awaitInputSource(modeID) else {
            fputs("error: input source not found: \(modeID)\n", stderr)
            return 1
        }
        if inputSourceBoolean(source, kTISPropertyInputSourceIsEnabled) {
            print("input source already enabled: \(modeID)")
        } else {
            let status = TISEnableInputSource(source)
            if status != noErr {
                fputs("warning: TISEnableInputSource returned \(status); logout will refresh it\n", stderr)
            }
        }
    case .select:
        guard let source = awaitInputSource(modeID) else {
            fputs("error: input source not found: \(modeID)\n", stderr)
            return 1
        }
        guard inputSourceBoolean(source, kTISPropertyInputSourceIsEnabled),
              inputSourceBoolean(source, kTISPropertyInputSourceIsSelectCapable) else {
            fputs("warning: \(modeID) is not selectable yet; logout will refresh it\n", stderr)
            return 0
        }
        if inputSourceBoolean(source, kTISPropertyInputSourceIsSelected) {
            print("input source already selected: \(modeID)")
            return 0
        }
        // -50 here means the caller is outside the logged-in user's GUI
        // session, which is what the installer's `launchctl asuser` avoids.
        let status = TISSelectInputSource(source)
        if status != noErr {
            fputs("warning: TISSelectInputSource returned \(status); logout will refresh it\n", stderr)
            return 0
        }
        print("selected input source: \(modeID)")
    }
    return 0
}

if CommandLine.arguments.count == 2,
   let command = InputSourceCommand(rawValue: CommandLine.arguments[1]) {
    exit(runInputSourceCommand(command))
}

final class InputMethodMain: NSObject, NSApplicationDelegate {
    private var server: IMKServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Candidate UI is a custom non-activating panel (`CandidateBarWindow`).
        // `IMKCandidates` is intentionally not created: it becomes key and
        // swallows digit / arrow events while visible.
        server = IMKServer(
            name: "VibeVoiceInputMethod_Connection",
            bundleIdentifier: "app.vibevoice.oss.inputmethod.pinyin"
        )
    }
}

let app = NSApplication.shared
let delegate = InputMethodMain()
app.delegate = delegate
app.run()
