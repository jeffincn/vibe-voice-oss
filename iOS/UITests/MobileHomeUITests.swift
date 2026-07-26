import XCTest

final class MobileHomeUITests: XCTestCase {
    /// The app follows the device language, so a test that asserts on visible
    /// text has to pin the language rather than inherit whatever the simulator
    /// or the CI runner happens to be set to.
    private func launchInChinese() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)",
            "-AppleLocale", "zh_Hans_CN",
        ]
        app.launch()
        return app
    }

    func testHomeExposesKeyboardVoiceAndModelControls() {
        let app = launchInChinese()

        XCTAssertTrue(app.staticTexts["home.hero"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["voice.record"].exists)
        XCTAssertTrue(app.segmentedControls["voice.outputMode"].exists)

        app.swipeUp()
        XCTAssertTrue(app.buttons["model.prepare"].waitForExistence(timeout: 3))
    }

    func testOutputModeCanBeChangedWithoutStartingModelDownload() {
        let app = launchInChinese()

        let picker = app.segmentedControls["voice.outputMode"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        let original = picker.buttons["原文"]
        XCTAssertTrue(original.exists)
        original.tap()
        XCTAssertTrue(original.isSelected)
    }
}
