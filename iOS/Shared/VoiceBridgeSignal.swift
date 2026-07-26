import Foundation

/// Darwin notifications tell the other process that the bridge file changed.
///
/// They carry no payload and the system coalesces them, so a signal only means
/// "re-read the file". Callers keep a slow timer as a backstop rather than
/// treating delivery as guaranteed.
enum VoiceBridgeSignal {
    static let notificationName = "app.vibevoice.oss.shared.voice-bridge-changed" as CFString

    static func postChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName),
            nil,
            nil,
            true
        )
    }
}

/// Calls `onChange` on the main queue whenever the other process signals, until
/// the watcher is deallocated.
final class VoiceBridgeWatcher {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<VoiceBridgeWatcher>.fromOpaque(observer)
                    .takeUnretainedValue()
                    .fire()
            },
            VoiceBridgeSignal.notificationName,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    private func fire() {
        DispatchQueue.main.async { [onChange] in
            onChange()
        }
    }
}
