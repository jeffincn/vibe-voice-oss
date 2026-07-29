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
        let input = app.textViews["playground.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["playground.reasoning"].exists)
        input.tap()
        input.typeText("你好")

        let send = app.buttons["playground.send"]
        XCTAssertTrue(send.isEnabled)
        send.tap()
        XCTAssertTrue(app.staticTexts["你好"].waitForExistence(timeout: 3))
    }

    func testInputPlaygroundEvidenceScreenshots() {
        let app = launchInChinese()
        let playground = app.buttons["playground.open"]
        XCTAssertTrue(playground.waitForExistence(timeout: 10))
        playground.tap()

        let input = app.textViews["playground.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("wodao le fangan de xianchang")

        let composing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        composing.name = "01-input-playground-pinyin-composing"
        composing.lifetime = .keepAlways
        add(composing)

        app.buttons["playground.send"].tap()
        XCTAssertTrue(app.staticTexts["wodao le fangan de xianchang"].waitForExistence(timeout: 3))

        let sent = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sent.name = "02-input-playground-message-sent"
        sent.lifetime = .keepAlways
        add(sent)
    }

    func testInputPlaygroundVibeVoiceKeyboardScreenshot() {
        let app = launchInChinese()
        let playground = app.buttons["playground.open"]
        XCTAssertTrue(playground.waitForExistence(timeout: 10))
        playground.tap()

        let input = app.textViews["playground.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()

        // The simulator keeps the custom keyboard in the international-keyboard
        // cycle. Cycle at most three times; if the host does not expose the
        // globe accessibility element, the test still verifies the Playground
        // without making a false claim about keyboard availability.
        let globe = app.buttons["Next keyboard"]
        if globe.waitForExistence(timeout: 2) {
            for index in 0..<3 {
                globe.tap()
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "keyboard-cycle-\(index + 1)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
        } else {
            // iOS 26's keyboard is not exposed in the app accessibility tree
            // on every simulator configuration. Use the known globe location
            // as a last-resort visual probe; the exported screenshot is still
            // inspected before claiming that Vibe Voice was selected.
            let globeCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.90))
            for index in 0..<3 {
                globeCoordinate.tap()
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "keyboard-coordinate-cycle-\(index + 1)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
        }
    }
}
