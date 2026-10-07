import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    func testGoalChangesPersistAndRejectInvalidValuesAndRecordedHistory() {
        let app = XCUIApplication()
        let title = "Goal walk"
        app.launchEnvironment["DAILYGO_UI_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 10))
        app.buttons["add-habit"].tap()
        app.textFields["habit-title"].tap()
        app.textFields["habit-title"].typeText(title)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        app.buttons["habit-goal"].tap()
        app.buttons["Steps"].tap()
        let target = app.textFields["habit-target"]
        target.tap()
        target.typeText("0")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Check the title, schedule, timezone and numeric value."].waitForExistence(timeout: 10))
        replaceNumericText(target, with: "1000")
        XCTAssertEqual(target.value as? String, "1000")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Record progress"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Record progress"].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertEqual(target.value as? String, "1000.0")
        app.buttons["Cancel"].tap()
        app.buttons["Record progress"].tap()
        let value = app.textFields["Manual value"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        value.tap()
        value.typeText("100")
        app.buttons["Save"].tap()
        XCTAssertTrue(value.waitForNonExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        replaceNumericText(target, with: "2000")
        XCTAssertEqual(target.value as? String, "2000")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Goals with recorded history cannot be changed yet."].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertEqual(target.value as? String, "1000.0")
    }

    private func replaceNumericText(_ field: XCUIElement, with value: String) {
        let current = field.value as? String ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
    }

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
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems["Select All"]
        if selectAll.waitForExistence(timeout: 2) {
            selectAll.tap()
        } else {
            let selectAllButton = app.buttons["Select All"]
            XCTAssertTrue(selectAllButton.waitForExistence(timeout: 2))
            selectAllButton.tap()
        }
        field.typeText(edited)
        XCTAssertEqual(field.value as? String, edited)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Archive"].tap()
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        let archived = app.switches["Archived"]
        archived.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(archived.value as? String, "1")
        XCTAssertTrue(app.staticTexts[edited].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Restore"].tap()
        XCTAssertTrue(app.staticTexts["No habits yet"].waitForExistence(timeout: 10))
        archived.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(archived.value as? String, "0")
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