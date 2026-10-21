import XCTest

final class ReferenceScenarioTests: XCTestCase {
    @MainActor
    func testReferenceScenarioIsVisiblySimulatedAndQualified() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["reading"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["reading"].label, "Simulated EV100 15.0")
        XCTAssertEqual(app.staticTexts["shutter"].label, "≈ 1/256 s")
        XCTAssertTrue(app.staticTexts["Program may choose another aperture."].exists)
    }
}
