import Foundation
import SQLite3

struct NativeLegacyIssue: Sendable { let entityID: String?; let code: String }
struct NativeLegacyReport: Sendable { let imported: Bool; let issues: [NativeLegacyIssue] }

private enum LegacyJSON: Codable, Equatable {
    case string(String), object([String: LegacyJSON]), number(Int)
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Int.self) { self = .number(value) }
        else { self = .object(try container.decode([String: LegacyJSON].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

private struct LegacyHabit: Codable, Equatable {
    static let fields: Set<String> = ["id", "title", "frequency", "metric", "created_at_utc", "is_archived"]
    let id: String
    let title: String
    let frequency: LegacyJSON
    let metric: LegacyJSON
    let created_at_utc: Int64
    let is_archived: Bool
}

private struct LegacyEntry: Codable, Equatable {
    static let fields: Set<String> = ["id", "habit_id", "timestamp_utc", "tz_offset_minutes", "local_date", "value", "verification_status", "sync_status"]
    let id: String
    let habit_id: String
    let timestamp_utc: Int64
    let tz_offset_minutes: Int
    let local_date: String
    let value: Double?
    let verification_status: String
    let sync_status: String
}

private struct LegacyEvent {
    let id: String
    let kind: String
    let entityID: String
    let payload: Data
    let instant: Int64
    let synced: Bool
}

enum NativeLegacy {
    static func read(url: URL, ownerID: String, zones: [String: String], acceptUnverified: Bool) throws -> (NativeBackup?, [NativeLegacyIssue]) {
        guard url.isFileURL else { throw NativeStorageError.invalidDefinition }
        try NativeStorageEncoding.validateIdentity(ownerID)
        var connection: OpaquePointer?
        guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw NativeStorageError.invalidDefinition
        }
        defer { sqlite3_close(connection) }
        try execute(connection, "BEGIN")
        let oldHabits: [LegacyHabit] = try query(connection, "SELECT id,title,frequency_json,metric_json,created_at_utc,is_archived FROM habits ORDER BY id") { statement in
            let archived = sqlite3_column_int64(statement, 5)
            guard archived == 0 || archived == 1 else { throw NativeStorageError.invalidDefinition }
            return LegacyHabit(id: try text(statement, 0), title: try text(statement, 1),
                frequency: try JSONDecoder().decode(LegacyJSON.self, from: Data(text(statement, 2).utf8)),
                metric: try JSONDecoder().decode(LegacyJSON.self, from: Data(text(statement, 3).utf8)),
                created_at_utc: sqlite3_column_int64(statement, 4), is_archived: archived == 1)
        }
        let oldEntries: [LegacyEntry] = try query(connection, "SELECT id,habit_id,timestamp_utc,tz_offset_minutes,local_date,value,verification_status,sync_status FROM check_in_records ORDER BY id") { statement in
            let offset = sqlite3_column_int64(statement, 3)
            guard (-1080...1080).contains(offset) else { throw NativeStorageError.invalidDefinition }
            return LegacyEntry(id: try text(statement, 0), habit_id: try text(statement, 1), timestamp_utc: sqlite3_column_int64(statement, 2),
                tz_offset_minutes: Int(offset), local_date: try text(statement, 4),
                value: sqlite3_column_type(statement, 5) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 5),
                verification_status: try text(statement, 6), sync_status: try text(statement, 7))
        }
        let oldEvents: [LegacyEvent] = try query(connection, "SELECT event_id,entity_type,entity_id,payload_json,created_at_utc,is_synced FROM sync_outbox ORDER BY created_at_utc,event_id") { statement in
            let synced = sqlite3_column_int64(statement, 5)
            guard synced == 0 || synced == 1 else { throw NativeStorageError.invalidDefinition }
            return LegacyEvent(id: try text(statement, 0), kind: try text(statement, 1), entityID: try text(statement, 2),
                payload: Data(try text(statement, 3).utf8), instant: sqlite3_column_int64(statement, 4), synced: synced == 1)
        }
        try execute(connection, "COMMIT")
        var issues = oldHabits.filter { zones[$0.id] == nil }.map { NativeLegacyIssue(entityID: $0.id, code: "TIMEZONE_REQUIRED") }
        issues += oldEntries.map { NativeLegacyIssue(entityID: $0.id, code: "UNVERIFIED_PROVENANCE") }
        guard oldHabits.allSatisfy({ zones[$0.id] != nil }), oldEntries.isEmpty || acceptUnverified else { return (nil, issues) }
        let habits = try oldHabits.map { old in
            let schedule: String
            let parameter: Int?
            switch old.frequency {
            case .string("Daily"): schedule = "daily"; parameter = nil
            case .string("Weekdays"): schedule = "weekdays"; parameter = nil
            case .object(let value):
                guard value.count == 1, case .object(let weekly) = value["WeeklyTarget"], weekly.count == 1,
                      case .number(let target) = weekly["times_per_week"] else { throw NativeStorageError.invalidDefinition }
                schedule = "weekly"; parameter = target
            default: throw NativeStorageError.invalidDefinition
            }
            let goal: String
            let target: Double?
            switch old.metric {
            case .string("Completion"): goal = "completion"; target = nil
            case .object(let value):
                guard value.count == 1, let kind = value.keys.first, case .object(let metric) = value[kind], metric.count == 1,
                      case .number(let amount) = metric["target"] else { throw NativeStorageError.invalidDefinition }
                switch kind {
                case "Steps": goal = "steps"
                case "DurationMinutes": goal = "duration_minutes"
                case "DistanceMeters": goal = "distance_meters"
                default: throw NativeStorageError.invalidDefinition
                }
                target = Double(amount)
            default: throw NativeStorageError.invalidDefinition
            }
            let habit = NativeHabit(ownerID: ownerID, id: old.id, title: old.title, scheduleKind: schedule, scheduleParameter: parameter,
                goalKind: goal, target: target, zoneID: zones[old.id]!, createdAtMillis: old.created_at_utc, archived: old.is_archived)
            _ = try habit.definition()
            return habit
        }
        var entries: [NativeEntry] = []
        for old in oldEntries {
            guard ["Verified", "SelfReported", "Suspect"].contains(old.verification_status), ["Pending", "Synced"].contains(old.sync_status),
                  let habit = habits.first(where: { $0.id == old.habit_id }), let zone = TimeZone(identifier: habit.zoneID),
                  zone.secondsFromGMT(for: NativeStorageEncoding.date(old.timestamp_utc)) == old.tz_offset_minutes * 60 else {
                throw NativeStorageError.invalidDefinition
            }
            let complete = try habit.definition().goal.isCompleted(value: old.value)
            guard complete || old.value != nil else { throw NativeStorageError.invalidDefinition }
            entries.append(NativeEntry(ownerID: ownerID, id: old.id, habitID: old.habit_id, kind: complete ? .completion : .progress,
                occurredAtMillis: old.timestamp_utc, creditedDate: old.local_date, zoneID: habit.zoneID, creditReason: .legacyImported, value: old.value))
            if old.sync_status == "Pending", !oldEvents.contains(where: { $0.kind == "CheckInCreated" && $0.entityID == old.id }) {
                throw NativeStorageError.invalidDefinition
            }
        }
        var events: [NativeEvent] = []
        var receipts: [NativeReceipt] = []
        for old in oldEvents {
            let kind: String
            let payload: Data
            let request: Data
            switch old.kind {
            case "HabitCreated":
                guard let source = oldHabits.first(where: { $0.id == old.entityID }),
                      try decode(LegacyHabit.self, payload: old.payload, fields: LegacyHabit.fields) == source,
                      let habit = habits.first(where: { $0.id == old.entityID }) else { throw NativeStorageError.invalidDefinition }
                kind = "habit.created"; payload = try NativeStorageEncoding.encode(habit); request = payload
            case "CheckInCreated":
                guard let source = oldEntries.first(where: { $0.id == old.entityID }),
                      try decode(LegacyEntry.self, payload: old.payload, fields: LegacyEntry.fields) == source,
                      let entry = entries.first(where: { $0.id == old.entityID }) else { throw NativeStorageError.invalidDefinition }
                kind = entry.kind == .completion ? "checkin.completed" : "progress.recorded"
                payload = try NativeStorageEncoding.encode(entry)
                request = try NativeEntryCommand(ownerID: ownerID, operationID: old.id, recordID: entry.id, habitID: entry.habitID,
                    occurredAtMillis: entry.occurredAtMillis, value: entry.value, workoutStartedAtMillis: nil, asOfMillis: nil).request()
            default: throw NativeStorageError.invalidDefinition
            }
            receipts.append(NativeReceipt(ownerID: ownerID, operationID: old.id, kind: kind, request: request, resultID: old.entityID))
            if !old.synced { events.append(NativeEvent(ownerID: ownerID, eventID: old.id, kind: kind, entityID: old.entityID, payload: payload, createdAtMillis: old.instant)) }
        }
        let backup = NativeBackup(ownerID: ownerID, habits: habits, entries: entries, events: events, receipts: receipts)
        try backup.validate(ownerID: ownerID)
        return (backup, issues)
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, payload: Data, fields: Set<String>) throws -> Value {
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any], Set(object.keys) == fields else {
            throw NativeStorageError.invalidDefinition
        }
        return try JSONDecoder().decode(type, from: payload)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT, let value = sqlite3_column_text(statement, column) else {
            throw NativeStorageError.invalidDefinition
        }
        return String(cString: value)
    }

    private static func execute(_ connection: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else { throw NativeStorageError.invalidDefinition }
    }

    private static func query<Value>(_ connection: OpaquePointer, _ sql: String, transform: (OpaquePointer) throws -> Value) throws -> [Value] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw NativeStorageError.invalidDefinition }
        defer { sqlite3_finalize(statement) }
        var results: [Value] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return results }
            guard code == SQLITE_ROW else { throw NativeStorageError.invalidDefinition }
            results.append(try transform(statement))
        }
    }
}