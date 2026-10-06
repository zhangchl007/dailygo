import Foundation

public enum MetricKind: String, Codable, Sendable { case steps, durationMinutes, distanceMeters }

public enum Goal: Equatable, Sendable {
    case completion
    case numeric(kind: MetricKind, target: Double)

    public func validate() throws {
        if case .numeric(let kind, let target) = self {
            guard target.isFinite, target > 0,
                  kind != .steps || target.rounded(.down) == target else { throw DomainError.invalidGoal }
        }
    }

    public func isCompleted(value: Double?) throws -> Bool {
        try validate()
        if let value {
            guard value.isFinite, value >= 0 else { throw DomainError.invalidGoal }
            if case .numeric(.steps, _) = self, value.rounded(.down) != value { throw DomainError.invalidGoal }
        }
        switch self {
        case .completion: return true
        case .numeric(_, let target): return value.map { $0 >= target } ?? false
        }
    }
}

public struct HabitDefinition: Sendable {
    public let title: String
    public let schedule: Schedule
    public let goal: Goal
    public let archived: Bool

    public init(title: String, schedule: Schedule, goal: Goal, archived: Bool = false) throws {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(trimmed.unicodeScalars.count),
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else { throw DomainError.invalidTitle }
        if case .weekly(let target) = schedule, !(1...7).contains(target) { throw DomainError.invalidSchedule }
        try goal.validate()
        self.title = trimmed
        self.schedule = schedule
        self.goal = goal
        self.archived = archived
    }

    public func isCompleted(value: Double?) throws -> Bool {
        guard !archived else { throw DomainError.archivedHabit }
        return try goal.isCompleted(value: value)
    }

    public func validateProgress(value: Double) throws {
        guard !archived else { throw DomainError.archivedHabit }
        guard case .numeric = goal, try !goal.isCompleted(value: value) else { throw DomainError.invalidGoal }
    }
}

public enum CreditReason: String, Codable, Sendable { case currentDay, midnightGrace }
public struct DateCredit: Sendable {
    public let date: LocalDay
    public let zoneID: String
    public let reason: CreditReason
}

public enum CalendarPolicy {
    public static func credit(
        now: Date, zoneID: String, workoutStartedAt: Date? = nil,
        previousComplete: Bool = false, graceHours: Int = 3
    ) throws -> DateCredit {
        guard (0...23).contains(graceHours), let zone = TimeZone(identifier: zoneID),
              zoneID == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(zoneID) else {
            throw DomainError.invalidConfiguration
        }
        guard now.timeIntervalSince1970.isFinite,
              workoutStartedAt.map({ $0.timeIntervalSince1970.isFinite && $0 <= now }) ?? true else {
            throw DomainError.invalidDate
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let today = try localDay(now, calendar: calendar)
        let previous = try today.adding(days: -1)
        let startedDay = try workoutStartedAt.map { try localDay($0, calendar: calendar) }
        if calendar.component(.hour, from: now) < graceHours,
           startedDay == previous, !previousComplete {
            return DateCredit(date: previous, zoneID: zoneID, reason: .midnightGrace)
        }
        return DateCredit(date: today, zoneID: zoneID, reason: .currentDay)
    }

    private static func localDay(_ date: Date, calendar: Calendar) throws -> LocalDay {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let normalized = LocalDay.calendar.date(from: components) else { throw DomainError.invalidDate }
        return try LocalDay(LocalDay.formatter().string(from: normalized))
    }
}

public enum HealthSource: String, Codable, Sendable { case healthKit, healthConnect, manual }
public enum EvidenceStatus: String, Codable, Sendable { case manual, unavailable, insufficient, healthBacked }

public struct HealthEvidence: Sendable {
    public let source: HealthSource
    public let startedAt: Date
    public let endedAt: Date
    public let steps: Double?
    public let durationMinutes: Double?
    public let distanceMeters: Double?

    public init(
        source: HealthSource, startedAt: Date, endedAt: Date,
        steps: Double? = nil, durationMinutes: Double? = nil, distanceMeters: Double? = nil
    ) throws {
        guard startedAt.timeIntervalSince1970.isFinite, endedAt.timeIntervalSince1970.isFinite,
              endedAt >= startedAt,
              [steps, durationMinutes, distanceMeters].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 >= 0 }),
              steps.map({ $0.rounded(.down) == $0 }) ?? true else { throw DomainError.invalidEvidence }
        self.source = source
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.steps = steps
        self.durationMinutes = durationMinutes
        self.distanceMeters = distanceMeters
    }
}

public enum EvidenceEvaluator {
    public static func assess(goal: Goal, evidence: HealthEvidence?) throws -> EvidenceStatus {
        try goal.validate()
        guard let evidence else { return .unavailable }
        guard evidence.source != .manual else { return .manual }
        let measurement: Double?
        switch goal {
        case .completion: measurement = [evidence.steps, evidence.durationMinutes, evidence.distanceMeters].compactMap { $0 }.max()
        case .numeric(let kind, _):
            switch kind {
            case .steps: measurement = evidence.steps
            case .durationMinutes: measurement = evidence.durationMinutes
            case .distanceMeters: measurement = evidence.distanceMeters
            }
        }
        guard let measurement else { return .unavailable }
        let meetsGoal = goal == .completion ? measurement > 0 : try goal.isCompleted(value: measurement)
        return meetsGoal ? .healthBacked : .insufficient
    }
}