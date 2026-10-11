import Foundation
import XCTest
@testable import DailyGoDomain

final class PolicyTests: XCTestCase {
    struct CalendarDocument: Decodable { let schemaVersion: Int; let cases: [CalendarFixture] }
    struct CalendarFixture: Decodable {
        let name: String
        let now: String
        let zone: String
        let started: String?
        let previousComplete: Bool?
        let graceHours: Int?
        let expected: String?
        let error: Bool?
    }

    func testCalendarFixtures() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let directory = ProcessInfo.processInfo.environment["DAILYGO_FIXTURES"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("tests/fixtures")
        let data = try Data(contentsOf: directory.appendingPathComponent("calendar.json"))
        let document = try JSONDecoder().decode(CalendarDocument.self, from: data)
        XCTAssertEqual(document.schemaVersion, 1)
        let formatter = ISO8601DateFormatter()
        for fixture in document.cases {
            func evaluate() throws -> String {
                let now = try XCTUnwrap(formatter.date(from: fixture.now))
                let started = try fixture.started.map { try XCTUnwrap(formatter.date(from: $0)) }
                return try CalendarPolicy.credit(
                    now: now, zoneID: fixture.zone, workoutStartedAt: started,
                    previousComplete: fixture.previousComplete ?? false, graceHours: fixture.graceHours ?? 3
                ).date.description
            }
            if fixture.error == true {
                XCTAssertThrowsError(try evaluate(), fixture.name)
            } else {
                XCTAssertEqual(try evaluate(), fixture.expected, fixture.name)
            }
        }
        print("Validated \(document.cases.count) shared calendar vectors")
    }

    func testTitleAndTargetValidation() throws {
        XCTAssertEqual(try HabitDefinition(title: "  Morning walk  ", schedule: .daily, goal: .completion).title, "Morning walk")
        for title in ["", "  ", String(repeating: "x", count: 101), String(repeating: "😀", count: 101)] {
            XCTAssertThrowsError(try HabitDefinition(title: title, schedule: .daily, goal: .completion))
        }
        XCTAssertEqual(try HabitDefinition(title: String(repeating: "😀", count: 100), schedule: .daily, goal: .completion).title.unicodeScalars.count, 100)
        for target in [0.0, -1.0, Double.nan, Double.infinity, 1.5] {
            XCTAssertThrowsError(try Goal.numeric(kind: .steps, target: target).validate())
        }
    }

    func testCompletionRequiresGoalAndActiveHabit() throws {
        let goal = Goal.numeric(kind: .distanceMeters, target: 5000)
        XCTAssertFalse(try goal.isCompleted(value: nil))
        XCTAssertFalse(try goal.isCompleted(value: 4999))
        XCTAssertTrue(try goal.isCompleted(value: 5000))
        XCTAssertTrue(try Goal.completion.isCompleted(value: nil))
        for value in [-1.0, Double.nan, Double.infinity] { XCTAssertThrowsError(try goal.isCompleted(value: value)) }
        let habit = try HabitDefinition(title: "Archived", schedule: .daily, goal: goal, archived: true)
        XCTAssertThrowsError(try habit.isCompleted(value: 6000))
    }

    func testPartialProgressRequiresAnActiveNumericHabit() throws {
        let steps = try HabitDefinition(title: "Walk", schedule: .daily, goal: .numeric(kind: .steps, target: 1000))
        XCTAssertNoThrow(try steps.validateProgress(value: 0))
        XCTAssertNoThrow(try steps.validateProgress(value: 400))
        for value in [-1.0, Double.nan, Double.infinity, 0.5, 1000.0, 1001.0] {
            XCTAssertThrowsError(try steps.validateProgress(value: value))
        }
        let distance = try HabitDefinition(title: "Run", schedule: .daily, goal: .numeric(kind: .distanceMeters, target: 1000))
        XCTAssertNoThrow(try distance.validateProgress(value: 400.5))
        let completion = try HabitDefinition(title: "Read", schedule: .daily, goal: .completion)
        XCTAssertThrowsError(try completion.validateProgress(value: 0))
        let archived = try HabitDefinition(title: "Walk", schedule: .daily, goal: .numeric(kind: .steps, target: 1000), archived: true)
        XCTAssertThrowsError(try archived.validateProgress(value: 400))
    }

    func testHealthReadWindowsAreExplicitBoundedAndNeverFutureDated() throws {
        let start = Date(timeIntervalSince1970: 1791280800)
        let end = start.addingTimeInterval(3600)
        let window = try HealthReadWindow(startedAt: start, endedAt: end, asOf: end)
        XCTAssertEqual(window.startedAt, start)
        XCTAssertEqual(window.endedAt, end)
        for (from, through, asOf) in [(start, start, end), (end, start, end), (start, end, start),
            (start, start.addingTimeInterval(32 * 86400), start.addingTimeInterval(32 * 86400))] {
            XCTAssertThrowsError(try HealthReadWindow(startedAt: from, endedAt: through, asOf: asOf))
        }
        XCTAssertThrowsError(try HealthReadWindow(startedAt: Date(timeIntervalSince1970: .nan), endedAt: end, asOf: end))
    }

    func testEvidenceIsSourceBackedAndMissingIsUnknown() throws {
        let goal = Goal.numeric(kind: .steps, target: 5000)
        let start = Date(timeIntervalSince1970: 1791280800)
        let end = start.addingTimeInterval(3600)
        XCTAssertEqual(try EvidenceEvaluator.assess(goal: goal, evidence: nil), .unavailable)
        XCTAssertEqual(try EvidenceEvaluator.assess(goal: goal, evidence: HealthEvidence(source: .manual, startedAt: start, endedAt: end, steps: 6000)), .manual)
        XCTAssertEqual(try EvidenceEvaluator.assess(goal: goal, evidence: HealthEvidence(source: .healthKit, startedAt: start, endedAt: end)), .unavailable)
        XCTAssertEqual(try EvidenceEvaluator.assess(goal: goal, evidence: HealthEvidence(source: .healthKit, startedAt: start, endedAt: end, steps: 3500)), .insufficient)
        XCTAssertEqual(try EvidenceEvaluator.assess(goal: goal, evidence: HealthEvidence(source: .healthKit, startedAt: start, endedAt: end, steps: 5000)), .healthBacked)
        XCTAssertThrowsError(try HealthEvidence(source: .healthKit, startedAt: start, endedAt: end, steps: .nan))
        XCTAssertThrowsError(try HealthEvidence(source: .healthKit, startedAt: end, endedAt: start))
    }
}