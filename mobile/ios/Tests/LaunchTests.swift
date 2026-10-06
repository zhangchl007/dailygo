import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    func testNativeApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["dailygo-brand"].waitForExistence(timeout: 10))
    }
}