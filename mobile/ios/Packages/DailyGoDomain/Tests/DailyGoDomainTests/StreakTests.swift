import Foundation
import XCTest
@testable import DailyGoDomain

final class StreakTests: XCTestCase {
    struct Document: Decodable {
        let schemaVersion: Int
        let cases: [Fixture]
    }

    struct Fixture: Decodable {
        struct Range: Decodable { let start: String; let days: Int }
        struct Expected: Decodable {
            let current: Int
            let longest: Int
            let total: Int
            let shields: Int
            let today: Bool
        }
        let name: String
        let schedule: String
        let target: Int?
        let asOf: String
        let dates: [String]?
        let ranges: [Range]?
        let expected: Expected?
        let error: Bool?
    }

    func testSharedFixtures() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let directory = ProcessInfo.processInfo.environment["DAILYGO_FIXTURES"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("tests/fixtures")
        let data = try Data(contentsOf: directory.appendingPathComponent("streaks.json"))
        let document = try JSONDecoder().decode(Document.self, from: data)
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(Set(document.cases.map(\.name)).count, document.cases.count)

        for fixture in document.cases {
            func evaluate() throws -> StreakSummary {
                let schedule: Schedule
                switch fixture.schedule {
                case "daily": schedule = .daily
                case "weekdays": schedule = .weekdays
                case "weekly": schedule = .weekly(target: try XCTUnwrap(fixture.target))
                default: throw DomainError.invalidSchedule
                }
                var dates = try (fixture.dates ?? []).map { try LocalDay($0) }
                for range in fixture.ranges ?? [] {
                    let start = try LocalDay(range.start)
                    for offset in 0..<range.days { dates.append(try start.adding(days: offset)) }
                }
                return try StreakCalculator.calculate(schedule: schedule, dates: dates, asOf: LocalDay(fixture.asOf))
            }
            if fixture.error == true {
                XCTAssertThrowsError(try evaluate(), fixture.name)
            } else {
                let expected = try XCTUnwrap(fixture.expected)
                let result = try evaluate()
                XCTAssertEqual(result.current, expected.current, fixture.name)
                XCTAssertEqual(result.longest, expected.longest, fixture.name)
                XCTAssertEqual(result.total, expected.total, fixture.name)
                XCTAssertEqual(result.shields, expected.shields, fixture.name)
                XCTAssertEqual(result.isCheckedInToday, expected.today, fixture.name)
            }
        }
        print("Validated \(document.cases.count) shared streak vectors")
    }
}