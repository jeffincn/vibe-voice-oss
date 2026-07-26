import AudioToolbox
import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

struct AudioOutputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioInputDeviceError: LocalizedError {
    case unavailable(String)
    case cannotSelect(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unavailable(name):
            "找不到录音设备“\(name)”。请确认它仍然连接，或在设置中重新选择。"
        case let .cannotSelect(name, status):
            "无法使用录音设备“\(name)”（Core Audio \(status)）。"
        }
    }
}

/// Snapshot of system playback route so opening a Bluetooth mic (HFP/SCO) does not steal headphones.
struct AudioOutputRouteSnapshot: Sendable {
    let outputDeviceID: AudioDeviceID?
    let systemOutputDeviceID: AudioDeviceID?
}

enum AudioInputDevices {
    /// One-time subscription to system-object device changes. Menu-bar agents that
    /// never subscribe can be left with a stale HAL device table after a USB replug
    /// or sleep/wake (App Nap suspends notification delivery); stale AudioDeviceIDs
    /// then fail every operation with 'nope' (1852797029) until the app restarts.
    private static let halSubscription: Void = {
        let queue = DispatchQueue(label: "app.vibevoice.oss.hal-listener")
        let selectors: [AudioObjectPropertySelector] = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        for selector in selectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                queue
            ) { _, _ in
                // Subscription itself is the point — it keeps this process's HAL
                // state current so later enumerations return live device IDs.
            }
        }
    }()

    static func ensureDeviceChangeSubscription() {
        _ = halSubscription
    }

    /// Resolve by UID and confirm the HAL object is actually alive — a stale ID can
    /// pass enumeration but fails every subsequent operation.
    static func resolveLive(uid: String) -> AudioInputDevice? {
        guard let device = resolve(uid: uid), isAlive(deviceID: device.id) else {
            return nil
        }
        return device
    }

    static func all() -> [AudioInputDevice] {
        deviceIDs().compactMap { id in
            guard hasStreams(id, scope: kAudioDevicePropertyScopeInput),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: id),
                  let name = stringProperty(kAudioObjectPropertyName, deviceID: id) else {
                return nil
            }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func allOutputs() -> [AudioOutputDevice] {
        deviceIDs().compactMap { id in
            guard hasStreams(id, scope: kAudioDevicePropertyScopeOutput),
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: id),
                  let name = stringProperty(kAudioObjectPropertyName, deviceID: id) else {
                return nil
            }
            return AudioOutputDevice(id: id, uid: uid, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func resolve(uid: String) -> AudioInputDevice? {
        if uid.isEmpty {
            guard let defaultID = defaultInputDeviceID() else { return nil }
            return all().first { $0.id == defaultID }
        }
        return all().first { $0.uid == uid }
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        readDefaultDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        readDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func defaultSystemOutputDeviceID() -> AudioDeviceID? {
        readDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    static func defaultOutputName() -> String {
        guard let id = defaultOutputDeviceID(),
              let name = stringProperty(kAudioObjectPropertyName, deviceID: id) else {
            return "未知输出设备"
        }
        return name
    }

    static func captureOutputRoute() -> AudioOutputRouteSnapshot {
        AudioOutputRouteSnapshot(
            outputDeviceID: defaultOutputDeviceID(),
            systemOutputDeviceID: defaultSystemOutputDeviceID()
        )
    }

    /// Re-apply headphones (or whatever was playing) after a mic open steals the route.
    @discardableResult
    static func restoreOutputRoute(_ snapshot: AudioOutputRouteSnapshot) -> Bool {
        var restored = false
        if let output = snapshot.outputDeviceID,
           defaultOutputDeviceID() != output {
            restored = setDefaultDevice(kAudioHardwarePropertyDefaultOutputDevice, id: output) || restored
        }
        if let system = snapshot.systemOutputDeviceID,
           defaultSystemOutputDeviceID() != system {
            restored = setDefaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice, id: system) || restored
        }
        return restored
    }

    /// Prefer the selected mic as the system default *input* only — never touch output here.
    @discardableResult
    static func setDefaultInputDevice(_ id: AudioDeviceID) -> Bool {
        setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, id: id)
    }

    /// Put back the system default input that a capture session repointed.
    ///
    /// Pinning the default is how the IO unit is made to wake on the chosen hardware,
    /// but it is a machine-wide setting: without this, picking a mic in Settings also
    /// silently changes which microphone every other app records from, and it stays
    /// changed after the app quits.
    @discardableResult
    static func restoreInputRoute(_ id: AudioDeviceID?) -> Bool {
        guard let id, defaultInputDeviceID() != id, isAlive(deviceID: id) else { return false }
        return setDefaultDevice(kAudioHardwarePropertyDefaultInputDevice, id: id)
    }

    static func isAlive(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &alive) == noErr else {
            return false
        }
        return alive != 0
    }

    static func isBluetooth(deviceID: AudioDeviceID) -> Bool {
        guard let transport = transportType(deviceID: deviceID) else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    static func transportType(deviceID: AudioDeviceID) -> AudioDevicePropertyID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = AudioDevicePropertyID(0)
        var size = UInt32(MemoryLayout<AudioDevicePropertyID>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr else {
            return nil
        }
        return transport
    }

    private static func deviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func readDefaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    @discardableResult
    private static func setDefaultDevice(
        _ selector: AudioObjectPropertySelector,
        id: AudioDeviceID
    ) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &value
        ) == noErr
    }

    private static func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr
            && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        deviceID: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value?.takeUnretainedValue() as String?
    }
}
