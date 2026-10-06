import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    func testRemindersRemainOptInAcrossRelaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["DAILYGO_UI_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        let reminder = app.switches["reminder-toggle"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 10))
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Daily at 8:00 PM"].exists)
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        app.buttons["settings"].tap()
        XCTAssertTrue(reminder.waitForExistence(timeout: 10))
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertEqual(app.alerts.count, 0)
    }

    func testNativeApplicationLaunches() {
        let app = XCUIApplication()
        let testStore = UUID().uuidString
        app.launchEnvironment["DAILYGO_UI_TEST_STORE"] = testStore
        app.launch()
        XCTAssertTrue(app.staticTexts["dailygo-brand"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Habits"].exists)
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        let title = "UI walk \(testStore)"
        let edited = "Evening \(testStore)"
        app.buttons["add-habit"].tap()
        app.textFields["habit-title"].tap()
        app.textFields["habit-title"].typeText(title)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit habit"].tap()
        let field = app.textFields["habit-title"]
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count))
        field.typeText(edited)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        app.switches["Archived"].tap()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Restore"].tap()
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        app.switches["Archived"].tap()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 10))
        app.buttons["Complete"].tap()
        XCTAssertTrue(app.buttons["Completed"].waitForExistence(timeout: 10))
        app.buttons["Undo completion"].tap()
        XCTAssertTrue(app.buttons["Restore completion"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Restore completion"].waitForExistence(timeout: 10))
        app.buttons["Restore completion"].tap()
        XCTAssertTrue(app.buttons["Completed"].waitForExistence(timeout: 10))
        app.buttons["Show recent history"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["history-grid"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Completed"].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Delete habit"].tap()
        app.buttons["Delete habit"].tap()
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "native-empty-startup"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["dailygo-brand"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
    }
}