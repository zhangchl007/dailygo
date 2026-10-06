import Foundation
import DailyGoDomain

struct AppOverview: Sendable {
    let date: LocalDay
    let summary: StreakSummary

    static func empty(now: Date, zoneID: String) throws -> AppOverview {
        let credit = try CalendarPolicy.credit(now: now, zoneID: zoneID)
        return try AppOverview(
            date: credit.date,
            summary: StreakCalculator.calculate(schedule: .daily, dates: [], asOf: credit.date)
        )
    }
}