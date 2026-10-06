import Foundation
import XCTest
@testable import DailyGo

final class AppOverviewTests: XCTestCase {
    func testStartupUsesLocalDateAndNativeDomain() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T17:30:00Z"))
        let result = try AppOverview.empty(now: now, zoneID: "Asia/Shanghai")
        XCTAssertEqual(result.date.description, "2026-10-07")
        XCTAssertEqual(result.summary.total, 0)
        XCTAssertFalse(result.summary.isCheckedInToday)
    }
}