import XCTest

final class ReferenceScenarioTests: XCTestCase {
    @MainActor
    func testReferenceScenarioAndModeChange() {
        let app = XCUIApplication()
        app.launchArguments = ["--reference-scenario"]
        app.launchArguments.append("--demo-meter")
        app.launch()
        XCTAssertTrue(app.staticTexts["reading"].waitForExistence(timeout: 20))
        app.swipeUp()
        XCTAssertEqual(app.staticTexts["shutter"].label, "≈ 1/256 s")
        XCTAssertTrue(app.staticTexts["Program may choose another aperture."].exists)
        app.buttons["filter-2"].tap()
        XCTAssertEqual(app.staticTexts["shutter"].label, "≈ 1/512 s")
        XCTAssertTrue(app.staticTexts["recommendation"].label.contains("ND8"))
        app.buttons["useRecommendation"].tap()
        XCTAssertEqual(app.staticTexts["shutter"].label, "≈ 1/256 s")
        app.swipeDown()
        app.segmentedControls["mode"].buttons["Bokeh"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["recommendation"].label.contains("ND32"))
        app.swipeDown()
        app.segmentedControls["mode"].buttons["Slow-speed"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["recommendation"].label.contains("ND8"))
        XCTAssertEqual(app.staticTexts["shutter"].label, "≈ 1/256 s")
        XCTAssertTrue(app.staticTexts["At target f/8"].exists)
        XCTAssertTrue(app.staticTexts["Program may choose another aperture."].exists)
    }
    #if targetEnvironment(simulator)
    @MainActor
    func testMissingSimulatorCameraOffersManualEntryWithoutFakeLiveResult() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["meterUnavailable"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["meterUnavailable"].label.contains("No rear camera"))
        XCTAssertFalse(app.staticTexts["reading"].exists)
        XCTAssertFalse(app.staticTexts["recommendation"].exists)
        app.buttons["manualEV"].tap()
        XCTAssertTrue(app.textFields["manualEVField"].waitForExistence(timeout: 5))
        app.buttons["applyManualEV"].tap()
        XCTAssertTrue(app.staticTexts["readingStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["readingStatus"].label.contains("Manual"))
    }

    #endif

    @MainActor
    func testHoldAndManualEntry() {
        let app = XCUIApplication(); app.launchArguments.append("--demo-meter")
        app.launch()
        XCTAssertTrue(app.buttons["holdResume"].waitForExistence(timeout: 20))
        app.buttons["holdResume"].tap()
        XCTAssertTrue(app.staticTexts["readingStatus"].label.contains("Held"))
        app.buttons["manualEV"].tap()
        let field = app.textFields["manualEVField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "8")
        app.buttons["applyManualEV"].tap()
        XCTAssertTrue(app.staticTexts["readingStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["readingStatus"].label.contains("Manual"))
        XCTAssertEqual(app.staticTexts["reading"].label, "EV100 8")
        app.buttons["holdResume"].tap()
        XCTAssertEqual(app.staticTexts["reading"].label, "EV100 15")
    }
}
