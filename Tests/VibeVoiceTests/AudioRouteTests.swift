import XCTest
@testable import VibeVoice

final class AudioRouteTests: XCTestCase {
    func testInputDeviceEnumerationIncludesUID() {
        let devices = AudioInputDevices.all()
        // CI / sandboxes may have zero devices; only assert shape when present.
        for device in devices {
            XCTAssertFalse(device.uid.isEmpty)
            XCTAssertFalse(device.name.isEmpty)
            XCTAssertNotEqual(device.id, 0)
            _ = AudioInputDevices.isAlive(deviceID: device.id)
            _ = AudioInputDevices.isBluetooth(deviceID: device.id)
        }
    }

    func testOutputRouteSnapshotRoundTripShape() {
        let snapshot = AudioInputDevices.captureOutputRoute()
        // Restoring the current route should be a no-op success path.
        _ = AudioInputDevices.restoreOutputRoute(snapshot)
        XCTAssertNotNil(AudioInputDevices.defaultOutputName())
    }
}
