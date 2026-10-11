import XCTest

@MainActor
final class LaunchTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testGoalChangesPersistAndRejectInvalidValuesAndRecordedHistory() {
        let app = XCUIApplication()
        let title = "Goal walk"
        app.launchEnvironment["DAILYGO_UI_TEST_STORE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["add-habit"].waitForExistence(timeout: 10))
        app.buttons["add-habit"].tap()
        awaitEditor(app)
        app.textFields["habit-title"].tap()
        app.textFields["habit-title"].typeText(title)
        app.buttons["Save"].tap()
        awaitEditorClosed(app)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        awaitEditor(app)
        let picker = app.descendants(matching: .any)["habit-goal"].firstMatch
        awaitHittable(picker)
        picker.tap()
        let steps = app.descendants(matching: .any)["Steps"].firstMatch
        awaitHittable(steps)
        steps.tap()
        let target = app.textFields["habit-target"]
        target.tap()
        target.typeText("0")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Check the title, schedule, timezone and numeric value."].waitForExistence(timeout: 10))
        replaceText(target, clearButton: app.buttons["clear-habit-target"], with: "1000", in: app)
        XCTAssertEqual(target.value as? String, "1000")
        app.buttons["Save"].tap()
        awaitEditorClosed(app)
        XCTAssertTrue(app.buttons["Record progress"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Record progress"].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        awaitEditor(app)
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertEqual(target.value as? String, "1000.0")
        app.buttons["Cancel"].tap()
        awaitEditorClosed(app)
        app.buttons["Record progress"].tap()
        let value = app.textFields["Manual value"]
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        value.tap()
        value.typeText("100")
        app.buttons["Save"].tap()
        XCTAssertTrue(value.waitForNonExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        awaitEditor(app)
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        replaceText(target, clearButton: app.buttons["clear-habit-target"], with: "2000", in: app)
        XCTAssertEqual(target.value as? String, "2000")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Goals with recorded history cannot be changed yet."].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        awaitEditorClosed(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit goal"].tap()
        awaitEditor(app)
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertEqual(target.value as? String, "1000.0")
    }

    private func awaitHittable(_ element: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func awaitEditor(_ app: XCUIApplication) {
        awaitHittable(app.descendants(matching: .any)["habit-editor"].firstMatch)
    }

    private func awaitEditorClosed(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["habit-editor"].firstMatch.waitForNonExistence(timeout: 10))
    }

    private func replaceText(_ field: XCUIElement, clearButton: XCUIElement, with value: String, in app: XCUIApplication) {
        awaitHittable(clearButton)
        clearButton.tap()
        XCTAssertTrue(clearButton.waitForNonExistence(timeout: 10))
        awaitHittable(field)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        field.typeText(value)
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
        awaitEditor(app)
        app.textFields["habit-title"].tap()
        app.textFields["habit-title"].typeText(title)
        app.buttons["Save"].tap()
        awaitEditorClosed(app)
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
        app.buttons["Habit options"].tap()
        app.buttons["Edit habit"].tap()
        awaitEditor(app)
        let field = app.textFields["habit-title"]
        replaceText(field, clearButton: app.buttons["clear-habit-title"], with: edited, in: app)
        XCTAssertEqual(field.value as? String, edited)
        app.buttons["Save"].tap()
        awaitEditorClosed(app)
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