import Carbon.HIToolbox
import Foundation

final class HotKeyManager {
    enum Event { case pressed, released }

    /// Fired for any registered mode chord. `mode` identifies which shortcut.
    var onEvent: ((RecordingOutputMode, Event) -> Void)?

    /// Chords another application already owns. Those shortcuts will never fire, and
    /// without this the failure was invisible: the user pressed ⌘⇧R and nothing happened.
    private(set) var unavailableModes: Set<RecordingOutputMode> = []
    /// True when the Carbon handler could not be installed, which kills every chord.
    private(set) var handlerUnavailable = false

    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var installedHandler = false
    private let signature = OSType(0x56564F53) // VVOS

    init() {
        installHandlerIfNeeded()
        registerAll()
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Re-register the mode shortcuts (idempotent).
    func registerAll() {
        installHandlerIfNeeded()
        unregisterAll()
        var unavailable: Set<RecordingOutputMode> = []
        for mode in RecordingOutputMode.allCases {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: signature, id: mode.carbonHotKeyID)
            let status = RegisterEventHotKey(
                mode.keyCode,
                mode.carbonModifiers,
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            guard status == noErr, let ref else {
                // Usually eventHotKeyExistsErr — another app holds the chord. There is
                // nothing to retry; the shortcut stays dead until that app releases it,
                // so the only useful response is to tell the user.
                unavailable.insert(mode)
                continue
            }
            hotKeys.append(ref)
        }
        unavailableModes = unavailable
    }

    private func installHandlerIfNeeded() {
        guard !installedHandler else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr,
                      hotKeyID.signature == manager.signature,
                      let mode = RecordingOutputMode.resolve(carbonHotKeyID: hotKeyID.id) else {
                    return OSStatus(eventNotHandledErr)
                }

                let kind = GetEventKind(event)
                if kind == UInt32(kEventHotKeyPressed) {
                    manager.onEvent?(mode, .pressed)
                    return noErr
                }
                if kind == UInt32(kEventHotKeyReleased) {
                    manager.onEvent?(mode, .released)
                    return noErr
                }
                return OSStatus(eventNotHandledErr)
            },
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        installedHandler = status == noErr
        handlerUnavailable = !installedHandler
    }

    private func unregisterAll() {
        for ref in hotKeys {
            UnregisterEventHotKey(ref)
        }
        hotKeys.removeAll()
    }
}
