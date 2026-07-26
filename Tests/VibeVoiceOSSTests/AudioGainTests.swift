import XCTest
@testable import VibeVoiceOSS

final class AudioGainTests: XCTestCase {
    func testQuietCaptureIsBroughtTowardTheTarget() {
        // A steady quiet tone: RMS and peak are close, so the RMS target decides.
        let gain = AudioRecorder.exportGain(rms: 0.02, peak: 0.03)
        XCTAssertEqual(gain, 5, accuracy: 0.01, "0.1 / 0.02 should be applied in full")
    }

    func testGainNeverExceedsTheAvailableHeadroom() {
        // Quiet voice with one loud transient. The RMS target asks for 8x; applying it
        // would push the transient to 4.0 and clip everything above -18 dBFS.
        let gain = AudioRecorder.exportGain(rms: 0.01, peak: 0.5)
        XCTAssertEqual(gain, 0.98 / 0.5, accuracy: 0.001)
        XCTAssertLessThanOrEqual(0.5 * gain, 1.0, "the loudest sample must stay in range")
    }

    func testAlreadyLoudCaptureIsLeftAlone() {
        let gain = AudioRecorder.exportGain(rms: 0.2, peak: 0.99)
        XCTAssertEqual(gain, 1, accuracy: 0.0001, "never attenuate, and never boost past full scale")
    }

    func testGainIsClampedAtEightEvenWithHeadroomToSpare() {
        // Near-silence: without the ceiling this would amplify room noise enormously.
        let gain = AudioRecorder.exportGain(rms: 0.000_1, peak: 0.001)
        XCTAssertEqual(gain, 8, accuracy: 0.001)
    }

    func testSilenceDoesNotDivideByZero() {
        let gain = AudioRecorder.exportGain(rms: 0, peak: 0)
        XCTAssertTrue(gain.isFinite)
        XCTAssertGreaterThanOrEqual(gain, 1)
    }
}
