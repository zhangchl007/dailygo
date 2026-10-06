import Foundation
import DailyGoDomain
import XCTest
@testable import DailyGo

final class AppOverviewTests: XCTestCase {
    func testHealthReadDoesNotInventSamplesOrAuthorization() async throws {
        let end = Date(timeIntervalSince1970: 1_791_282_600)
        let window = try HealthReadWindow(startedAt: end.addingTimeInterval(-3600), endedAt: end, asOf: end)
        let service = NativeHealthService()
        let reading = await service.readSteps(window: window)
        if !NativeHealthService.available { XCTAssertEqual(reading.status, .unavailable) }
        if reading.status == .available {
            XCTAssertNotNil(reading.evidence)
            XCTAssertFalse(reading.sourceIdentifiers.isEmpty)
            XCTAssertEqual(reading.evidence?.startedAt, window.startedAt)
            XCTAssertEqual(reading.evidence?.endedAt, window.endedAt)
        } else {
            XCTAssertNil(reading.evidence)
            XCTAssertTrue(reading.sourceIdentifiers.isEmpty)
        }
    }

    func testStartupUsesLocalDateAndNativeDomain() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-06T17:30:00Z"))
        let result = try AppOverview.empty(now: now, zoneID: "Asia/Shanghai")
        XCTAssertEqual(result.date.description, "2026-10-07")
        XCTAssertEqual(result.summary.total, 0)
        XCTAssertFalse(result.summary.isCheckedInToday)
    }
}