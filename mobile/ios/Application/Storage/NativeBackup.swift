import Foundation
import DailyGoDomain

struct NativeBackup: Codable, Sendable {
    var format = "dailygo.ios.backup"
    var version = 1
    let ownerID: String
    let habits: [NativeHabit]
    let entries: [NativeEntry]
    let events: [NativeEvent]
    let receipts: [NativeReceipt]

    func validate(ownerID expectedOwner: String) throws {
        try NativeStorageEncoding.validateIdentity(expectedOwner)
        guard format == "dailygo.ios.backup", version == 1, ownerID == expectedOwner else { throw NativeStorageError.invalidDefinition }
        func identities(_ records: [(String, String)]) throws {
            guard records.allSatisfy({ $0.0 == ownerID }), Set(records.map(\.1)).count == records.count else {
                throw NativeStorageError.invalidDefinition
            }
            for record in records { try NativeStorageEncoding.validateIdentity(record.0, record.1) }
        }
        try identities(habits.map { ($0.ownerID, $0.id) })
        for kind in [NativeEntryKind.completion, .progress] { try identities(entries.filter { $0.kind == kind }.map { ($0.ownerID, $0.id) }) }
        try identities(events.map { ($0.ownerID, $0.eventID) })
        try identities(receipts.map { ($0.ownerID, $0.operationID) })
        let definitions = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        for habit in habits { _ = try habit.definition() }
        var dates = Set<String>()
        for entry in entries {
            guard let habit = definitions[entry.habitID] else { throw NativeStorageError.missingHabit }
            _ = try LocalDay(entry.creditedDate)
            _ = try CalendarPolicy.credit(now: NativeStorageEncoding.date(entry.occurredAtMillis), zoneID: entry.zoneID)
            let goal = try habit.definition().goal
            switch entry.kind {
            case .completion:
                guard try goal.isCompleted(value: entry.value), dates.insert(try NativeStorageEncoding.key(entry.habitID, entry.creditedDate)).inserted else {
                    throw NativeStorageError.invalidDefinition
                }
            case .progress:
                guard case .numeric = goal, let value = entry.value, try !goal.isCompleted(value: value) else { throw NativeStorageError.invalidDefinition }
            }
        }
        let operations = Dictionary(uniqueKeysWithValues: receipts.map { ($0.operationID, $0) })
        for receipt in receipts {
            if receipt.kind == "habit.created" {
                let request = try NativeStorageEncoding.decode(NativeHabit.self, from: receipt.request)
                _ = try request.definition()
                guard request.ownerID == ownerID, request.id == receipt.resultID, definitions[request.id] != nil else { throw NativeStorageError.invalidDefinition }
                guard receipt.resultKey == nil || receipt.resultKey == request.id else { throw NativeStorageError.invalidDefinition }
            } else {
                guard receipt.kind == "progress.recorded" || receipt.kind == "checkin.completed" else { throw NativeStorageError.invalidDefinition }
                let request = try NativeStorageEncoding.decode(NativeEntryCommand.self, from: receipt.request)
                try request.validate()
                let kind: NativeEntryKind = receipt.kind == "progress.recorded" ? .progress : .completion
                guard request.ownerID == ownerID, request.operationID == receipt.operationID,
                      let result = entries.first(where: { $0.kind == kind && $0.id == receipt.resultID }), result.habitID == request.habitID else {
                    throw NativeStorageError.invalidDefinition
                }
                if kind == .progress {
                    guard result.id == request.recordID, result.value == request.value, result.occurredAtMillis == request.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
                } else {
                    guard let habit = definitions[request.habitID], try habit.definition().goal.isCompleted(value: request.value) else { throw NativeStorageError.invalidDefinition }
                }
                let resultKey = kind == .completion ? try NativeStorageEncoding.key(result.habitID, result.creditedDate) : result.id
                guard receipt.resultKey == nil || receipt.resultKey == resultKey else { throw NativeStorageError.invalidDefinition }
            }
        }
        for event in events {
            guard let receipt = operations[event.eventID], receipt.kind == event.kind, receipt.resultID == event.entityID else { throw NativeStorageError.invalidDefinition }
            if event.kind == "habit.created" {
                let payload = try NativeStorageEncoding.decode(NativeHabit.self, from: event.payload)
                let original = try NativeStorageEncoding.decode(NativeHabit.self, from: receipt.request)
                guard original == payload else { throw NativeStorageError.invalidDefinition }
            } else {
                let payload = try NativeStorageEncoding.decode(NativeEntry.self, from: event.payload)
                let kind: NativeEntryKind = event.kind == "progress.recorded" ? .progress : .completion
                guard payload.kind == kind, entries.contains(payload), payload.id == event.entityID else { throw NativeStorageError.invalidDefinition }
            }
        }
    }
}