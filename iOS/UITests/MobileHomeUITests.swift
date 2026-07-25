import XCTest

final class MobileHomeUITests: XCTestCase {
    func testHomeExposesKeyboardVoiceAndModelControls() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["home.hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice.record"].exists)
        XCTAssertTrue(app.segmentedControls["voice.outputMode"].exists)

        app.swipeUp()
        XCTAssertTrue(app.buttons["model.prepare"].waitForExistence(timeout: 3))
    }

    func testOutputModeCanBeChangedWithoutStartingModelDownload() {
        let app = XCUIApplication()
        app.launch()

        let picker = app.segmentedControls["voice.outputMode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let original = picker.buttons["原文"]
        XCTAssertTrue(original.exists)
        original.tap()
        XCTAssertTrue(original.isSelected)
    }
}
