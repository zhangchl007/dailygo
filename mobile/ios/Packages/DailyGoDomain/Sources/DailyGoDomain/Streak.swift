import Foundation

public enum DomainError: Error, Equatable {
    case invalidDate
    case invalidSchedule
    case futureDate
    case invalidConfiguration
    case invalidGoal
    case invalidTitle
    case archivedHabit
    case invalidEvidence
}

public struct LocalDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let date: Date
    public let description: String

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    public init(_ value: String) throws {
        let formatter = Self.formatter()
        guard value.utf8.count == 10, let date = formatter.date(from: value),
              formatter.string(from: date) == value else { throw DomainError.invalidDate }
        self.date = date
        self.description = value
    }

    public init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    public static func < (left: LocalDay, right: LocalDay) -> Bool { left.date < right.date }

    public func adding(days: Int) throws -> LocalDay {
        guard let result = Self.calendar.date(byAdding: .day, value: days, to: date) else {
            throw DomainError.invalidDate
        }
        return try LocalDay(Self.formatter().string(from: result))
    }

    var isoWeekday: Int { (Self.calendar.component(.weekday, from: date) + 5) % 7 + 1 }
    func weekStart() throws -> LocalDay { try adding(days: 1 - isoWeekday) }
    func days(until other: LocalDay) -> Int {
        Self.calendar.dateComponents([.day], from: date, to: other.date).day ?? 0
    }

    static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

public enum Schedule: Equatable, Sendable {
    case daily
    case weekdays
    case weekly(target: Int)
}

public enum StreakUnit: String, Sendable { case days, weeks }

public struct StreakSummary: Equatable, Sendable {
    public let current: Int
    public let longest: Int
    public let total: Int
    public let shields: Int
    public let isCheckedInToday: Bool
    public let lastCheckInDate: LocalDay?
    public let unit: StreakUnit
}

public enum StreakCalculator {
    public static func calculate(
        schedule: Schedule, dates: [LocalDay], asOf: LocalDay,
        periodsPerShield: Int = 7, maxShields: Int = 3
    ) throws -> StreakSummary {
        guard periodsPerShield > 0, maxShields >= 0 else { throw DomainError.invalidConfiguration }
        guard !dates.contains(where: { $0 > asOf }) else { throw DomainError.futureDate }
        let distinct = Array(Set(dates)).sorted()
        let completed: [LocalDay]
        let unit: StreakUnit
        switch schedule {
        case .daily:
            completed = distinct
            unit = .days
        case .weekdays:
            completed = distinct.filter { $0.isoWeekday <= 5 }
            unit = .days
        case .weekly(let target):
            guard (1...7).contains(target) else { throw DomainError.invalidSchedule }
            var counts: [LocalDay: Int] = [:]
            for day in distinct { counts[try day.weekStart(), default: 0] += 1 }
            completed = counts.filter { $0.value >= target }.keys.sorted()
            unit = .weeks
        }

        var current = 0
        var longest = 0
        var shields = 0
        var earningProgress = 0
        var previous: LocalDay?

        func miss(_ count: Int) {
            guard count > 0 else { return }
            let used = min(count, shields)
            shields -= used
            if count > used { current = 0 }
            earningProgress = 0
        }

        for period in completed {
            if let previous { miss(try missingBetween(schedule, previous, period)) }
            current += 1
            longest = max(longest, current)
            earningProgress += 1
            if earningProgress == periodsPerShield {
                shields = min(maxShields, shields + 1)
                earningProgress = 0
            }
            previous = period
        }

        if let previous {
            let openPeriod = unit == .weeks ? try asOf.weekStart() : asOf
            miss(try missingBetween(schedule, previous, openPeriod))
        }

        return StreakSummary(
            current: current, longest: longest, total: distinct.count, shields: shields,
            isCheckedInToday: distinct.contains(asOf), lastCheckInDate: distinct.last, unit: unit
        )
    }

    private static func missingBetween(_ schedule: Schedule, _ previous: LocalDay, _ next: LocalDay) throws -> Int {
        guard next > previous else { return 0 }
        switch schedule {
        case .daily: return max(0, previous.days(until: next) - 1)
        case .weekly: return max(0, previous.days(until: next) / 7 - 1)
        case .weekdays:
            let start = try previous.adding(days: 1)
            let days = start.days(until: next)
            let fullWeeks = days / 7
            var remainder = 0
            for offset in 0..<(days % 7) {
                if try start.adding(days: fullWeeks * 7 + offset).isoWeekday <= 5 { remainder += 1 }
            }
            return fullWeeks * 5 + remainder
        }
    }
}