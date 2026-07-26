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

    func testInputPlaygroundSupportsChatComposer() {
        let app = launchInChinese()

        let playground = app.buttons["playground.open"]
        XCTAssertTrue(playground.waitForExistence(timeout: 10))
        playground.tap()

        XCTAssertTrue(app.navigationBars["Vibe Voice 测试对话"].waitForExistence(timeout: 5))
        let input = app.textFields["playground.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("你好")

        let send = app.buttons["playground.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.staticTexts["你好"].waitForExistence(timeout: 3))
    }
}
