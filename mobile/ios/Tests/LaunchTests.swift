import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    func testNativeApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["dailygo-brand"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Habits"].exists)
        XCTAssertTrue(app.staticTexts["No habits yet"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-empty-startup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["dailygo-brand"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No habits yet"].exists)
    }
}