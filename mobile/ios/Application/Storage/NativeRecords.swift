import Foundation
import DailyGoDomain

enum NativeStorageError: Error, Equatable {
    case invalidIdentity, invalidDefinition, missingHabit, operationConflict, duplicateEntity, missingResult, deletedOwner, invalidStore
    case goalHasHistory
    case scheduleHasHistory
}

struct NativeHabit: Codable, Equatable, Sendable {
    let ownerID: String
    let id: String
    let title: String
    let scheduleKind: String
    let scheduleParameter: Int?
    let goalKind: String
    let target: Double?
    let zoneID: String
    let createdAtMillis: Int64
    let archived: Bool

    func definition() throws -> HabitDefinition {
        let schedule: Schedule
        switch scheduleKind {
        case "daily":
            guard scheduleParameter == nil else { throw NativeStorageError.invalidDefinition }
            schedule = .daily
        case "weekdays":
            guard scheduleParameter == nil else { throw NativeStorageError.invalidDefinition }
            schedule = .weekdays
        case "weekly":
            guard let parameter = scheduleParameter else { throw NativeStorageError.invalidDefinition }
            schedule = .weekly(target: parameter)
        default: throw NativeStorageError.invalidDefinition
        }
        let goal: Goal
        switch goalKind {
        case "completion":
            guard target == nil else { throw NativeStorageError.invalidDefinition }
            goal = .completion
        case "steps", "duration_minutes", "distance_meters":
            guard let target else { throw NativeStorageError.invalidDefinition }
            let kind: MetricKind = goalKind == "steps" ? .steps : (goalKind == "duration_minutes" ? .durationMinutes : .distanceMeters)
            goal = .numeric(kind: kind, target: target)
        default: throw NativeStorageError.invalidDefinition
        }
        let definition = try HabitDefinition(title: title, schedule: schedule, goal: goal, archived: archived)
        guard definition.title == title else { throw NativeStorageError.invalidDefinition }
        _ = try CalendarPolicy.credit(now: NativeStorageEncoding.date(createdAtMillis), zoneID: zoneID)
        return definition
    }
}

enum NativeEntryKind: String, Codable, Sendable { case completion, progress }

struct NativeCompletionCorrectionCommand: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let recordID: String
    let active: Bool
    let occurredAtMillis: Int64
    var asOfMillis: Int64? = nil

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, recordID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
    }
}

struct NativeCompletionState: Codable, Equatable, Sendable {
    let ownerID: String
    let recordID: String
    let active: Bool
    let operationID: String
    let occurredAtMillis: Int64
}

struct NativeHabitDeletion: Codable, Equatable, Sendable {
    let ownerID: String
    let habitID: String
    let operationID: String
    let occurredAtMillis: Int64
}

struct NativeRetiredHabitOperation: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let habitID: String
}

struct NativeHabitDeleteCommand: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let habitID: String
    let occurredAtMillis: Int64
    var asOfMillis: Int64? = nil

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, habitID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
    }
}

struct NativeHabitEditCommand: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let habitID: String
    let title: String
    let scheduleKind: String
    let scheduleParameter: Int?
    let zoneID: String
    let occurredAtMillis: Int64
    var asOfMillis: Int64? = nil

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, habitID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
    }

    func applying(to habit: NativeHabit) throws -> NativeHabit {
        try validate()
        guard ownerID == habit.ownerID, habitID == habit.id, occurredAtMillis >= habit.createdAtMillis else {
            throw NativeStorageError.invalidDefinition
        }
        let updated = NativeHabit(ownerID: habit.ownerID, id: habit.id, title: title, scheduleKind: scheduleKind,
            scheduleParameter: scheduleParameter, goalKind: habit.goalKind, target: habit.target,
            zoneID: zoneID, createdAtMillis: habit.createdAtMillis, archived: habit.archived)
        _ = try updated.definition()
        return updated
    }
}

struct NativeHabitGoalCommand: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let habitID: String
    let goalKind: String
    let target: Double?
    let occurredAtMillis: Int64
    var asOfMillis: Int64? = nil

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, habitID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
    }

    func applying(to habit: NativeHabit) throws -> NativeHabit {
        try validate()
        guard ownerID == habit.ownerID, habitID == habit.id, occurredAtMillis >= habit.createdAtMillis else {
            throw NativeStorageError.invalidDefinition
        }
        let updated = NativeHabit(ownerID: habit.ownerID, id: habit.id, title: habit.title,
            scheduleKind: habit.scheduleKind, scheduleParameter: habit.scheduleParameter,
            goalKind: goalKind, target: target, zoneID: habit.zoneID,
            createdAtMillis: habit.createdAtMillis, archived: habit.archived)
        _ = try updated.definition()
        return updated
    }
}

struct NativeHabitArchiveCommand: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let habitID: String
    let archived: Bool
    let occurredAtMillis: Int64
    var asOfMillis: Int64? = nil

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, habitID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
    }
}

struct NativeEntryCommand: Codable, Sendable {
    let ownerID: String
    let operationID: String
    let recordID: String
    let habitID: String
    let occurredAtMillis: Int64
    let value: Double?
    let workoutStartedAtMillis: Int64?
    var asOfMillis: Int64?
    var correctsRecordID: String? = nil
    var provenance: NativeEntryProvenance? = .manual

    init(
        ownerID: String,
        operationID: String,
        recordID: String,
        habitID: String,
        occurredAtMillis: Int64,
        value: Double?,
        workoutStartedAtMillis: Int64?,
        asOfMillis: Int64?,
        correctsRecordID: String? = nil,
        provenance: NativeEntryProvenance? = .manual
    ) {
        self.ownerID = ownerID
        self.operationID = operationID
        self.recordID = recordID
        self.habitID = habitID
        self.occurredAtMillis = occurredAtMillis
        self.value = value
        self.workoutStartedAtMillis = workoutStartedAtMillis
        self.asOfMillis = asOfMillis
        self.correctsRecordID = correctsRecordID
        self.provenance = provenance
    }

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, recordID, habitID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
        guard workoutStartedAtMillis.map({ $0 <= occurredAtMillis }) ?? true else { throw DomainError.invalidDate }
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID, operationID, recordID, habitID, occurredAtMillis, value, workoutStartedAtMillis
        case asOfMillis, correctsRecordID, provenance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try values.decode(String.self, forKey: .ownerID)
        operationID = try values.decode(String.self, forKey: .operationID)
        recordID = try values.decode(String.self, forKey: .recordID)
        habitID = try values.decode(String.self, forKey: .habitID)
        occurredAtMillis = try values.decode(Int64.self, forKey: .occurredAtMillis)
        value = try values.decodeIfPresent(Double.self, forKey: .value)
        workoutStartedAtMillis = try values.decodeIfPresent(Int64.self, forKey: .workoutStartedAtMillis)
        asOfMillis = try values.decodeIfPresent(Int64.self, forKey: .asOfMillis)
        correctsRecordID = try values.decodeIfPresent(String.self, forKey: .correctsRecordID)
        provenance = try values.decodeIfPresent(NativeEntryProvenance.self, forKey: .provenance)
    }
}

enum NativeEntryProvenance: String, Codable, Equatable, Sendable {
    case manual, healthKit, healthConnect, legacyImported

    var localizationKey: String {
        switch self {
        case .manual: "Manual"
        case .healthKit: "HealthKit"
        case .healthConnect: "Health Connect"
        case .legacyImported: "Imported (unverified)"
        }
    }
}

struct NativeCompletionValueCorrectionCommand: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let recordID: String
    let value: Double
    let occurredAtMillis: Int64
    var asOfMillis: Int64? = nil

    func request() throws -> Data {
        var normalized = self
        normalized.asOfMillis = nil
        return try NativeStorageEncoding.encode(normalized)
    }

    func validate() throws {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID, recordID)
        guard occurredAtMillis <= (asOfMillis ?? occurredAtMillis) else { throw DomainError.futureDate }
    }
}

struct NativeCompletionValueCorrection: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let recordID: String
    let revision: Int
    let value: Double
    let occurredAtMillis: Int64
}

struct NativeEntry: Codable, Equatable, Sendable {
    let ownerID: String
    let id: String
    let habitID: String
    let kind: NativeEntryKind
    let occurredAtMillis: Int64
    let creditedDate: String
    let zoneID: String
    let creditReason: CreditReason
    let value: Double?
    let provenance: NativeEntryProvenance?

    init(
        ownerID: String,
        id: String,
        habitID: String,
        kind: NativeEntryKind,
        occurredAtMillis: Int64,
        creditedDate: String,
        zoneID: String,
        creditReason: CreditReason,
        value: Double?,
        provenance: NativeEntryProvenance? = .manual
    ) {
        self.ownerID = ownerID
        self.id = id
        self.habitID = habitID
        self.kind = kind
        self.occurredAtMillis = occurredAtMillis
        self.creditedDate = creditedDate
        self.zoneID = zoneID
        self.creditReason = creditReason
        self.value = value
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case ownerID, id, habitID, kind, occurredAtMillis, creditedDate, zoneID, creditReason, value, provenance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try values.decode(String.self, forKey: .ownerID)
        id = try values.decode(String.self, forKey: .id)
        habitID = try values.decode(String.self, forKey: .habitID)
        kind = try values.decode(NativeEntryKind.self, forKey: .kind)
        occurredAtMillis = try values.decode(Int64.self, forKey: .occurredAtMillis)
        creditedDate = try values.decode(String.self, forKey: .creditedDate)
        zoneID = try values.decode(String.self, forKey: .zoneID)
        creditReason = try values.decode(CreditReason.self, forKey: .creditReason)
        value = try values.decodeIfPresent(Double.self, forKey: .value)
        provenance = try values.decodeIfPresent(NativeEntryProvenance.self, forKey: .provenance)
    }
}

struct NativeEvent: Codable, Equatable, Sendable {
    let ownerID: String
    let eventID: String
    let kind: String
    let entityID: String
    let payload: Data
    let createdAtMillis: Int64
}

struct NativeReceipt: Codable, Equatable, Sendable {
    let ownerID: String
    let operationID: String
    let kind: String
    let request: Data
    let resultID: String
    var resultKey: String? = nil
}

enum NativeStorageEncoding {
    static func decode<Value: Codable>(_ type: Value.Type, from data: Data) throws -> Value {
        let value = try JSONDecoder().decode(type, from: data)
        let original = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let canonical = try JSONSerialization.jsonObject(with: encode(value)) as? NSDictionary
        guard let original, let canonical, original == canonical else { throw NativeStorageError.invalidDefinition }
        return value
    }

    static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func key(_ components: String...) throws -> String {
        try encode(components).base64EncodedString()
    }

    static func validateIdentity(_ values: String...) throws {
        guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.unicodeScalars.count <= 128 && $0.rangeOfCharacter(from: .controlCharacters) == nil }) else {
            throw NativeStorageError.invalidIdentity
        }
    }

    static func date(_ millis: Int64) -> Date { Date(timeIntervalSince1970: Double(millis) / 1000) }
}