import Foundation
import SwiftData
import DailyGoDomain

@ModelActor
actor NativeRepository {
    func saveHabit(_ habit: NativeHabit, operationID: String) throws -> NativeHabit {
        try NativeStorageEncoding.validateIdentity(habit.ownerID, habit.id, operationID)
        _ = try habit.definition()
        let request = try NativeStorageEncoding.encode(habit)
        return try mutate {
            if let previous = try receipt(ownerID: habit.ownerID, operationID: operationID) {
                guard previous.kind == "habit.created", previous.request == request else { throw NativeStorageError.operationConflict }
                guard let row = try row(ownerID: habit.ownerID, category: "habit", keyID: previous.resultID) else {
                    throw NativeStorageError.missingResult
                }
                return try decode(NativeHabit.self, row)
            }
            try append(ownerID: habit.ownerID, category: "habit", identifier: habit.id, keyID: habit.id, value: habit)
            try appendEvent(NativeEvent(ownerID: habit.ownerID, eventID: operationID, kind: "habit.created", entityID: habit.id,
                                        payload: request, createdAtMillis: habit.createdAtMillis))
            try appendReceipt(NativeReceipt(ownerID: habit.ownerID, operationID: operationID, kind: "habit.created",
                                            request: request, resultID: habit.id))
            return habit
        }
    }

    func recordProgress(_ command: NativeEntryCommand) throws -> NativeEntry { try writeEntry(command, kind: .progress) }
    func complete(_ command: NativeEntryCommand) throws -> NativeEntry { try writeEntry(command, kind: .completion) }

    func entries(ownerID: String, habitID: String, kind: NativeEntryKind) throws -> [NativeEntry] {
        try NativeStorageEncoding.validateIdentity(ownerID, habitID)
        return try rows(ownerID: ownerID, category: kind.rawValue).map { try decode(NativeEntry.self, $0) }
            .filter { $0.habitID == habitID }
            .sorted { ($0.creditedDate, $0.occurredAtMillis, $0.id) < ($1.creditedDate, $1.occurredAtMillis, $1.id) }
    }

    func habits(ownerID: String) throws -> [NativeHabit] {
        try NativeStorageEncoding.validateIdentity(ownerID)
        return try rows(ownerID: ownerID, category: "habit").map { try decode(NativeHabit.self, $0) }
            .sorted { ($0.createdAtMillis, $0.id) < ($1.createdAtMillis, $1.id) }
    }

    func events(ownerID: String) throws -> [NativeEvent] {
        try NativeStorageEncoding.validateIdentity(ownerID)
        return try rows(ownerID: ownerID, category: "event").map { try decode(NativeEvent.self, $0) }
            .sorted { ($0.createdAtMillis, $0.eventID) < ($1.createdAtMillis, $1.eventID) }
    }

    func receipt(ownerID: String, operationID: String) throws -> NativeReceipt? {
        try NativeStorageEncoding.validateIdentity(ownerID, operationID)
        return try row(ownerID: ownerID, category: "receipt", keyID: operationID).map { try decode(NativeReceipt.self, $0) }
    }

    func acknowledge(ownerID: String, eventID: String) throws {
        try NativeStorageEncoding.validateIdentity(ownerID, eventID)
        try mutate {
            if let event = try row(ownerID: ownerID, category: "event", keyID: eventID) { modelContext.delete(event) }
        }
    }

    private func writeEntry(_ command: NativeEntryCommand, kind: NativeEntryKind) throws -> NativeEntry {
        try command.validate()
        let request = try command.request()
        let eventKind = kind == .completion ? "checkin.completed" : "progress.recorded"
        return try mutate {
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == eventKind, previous.request == request else { throw NativeStorageError.operationConflict }
                guard let row = try entryRow(ownerID: command.ownerID, category: kind.rawValue, identifier: previous.resultID) else {
                    throw NativeStorageError.missingResult
                }
                return try decode(NativeEntry.self, row)
            }
            guard let habitRow = try row(ownerID: command.ownerID, category: "habit", keyID: command.habitID) else {
                throw NativeStorageError.missingHabit
            }
            let habit = try decode(NativeHabit.self, habitRow)
            let definition = try habit.definition()
            if kind == .progress {
                guard let value = command.value else { throw DomainError.invalidGoal }
                try definition.validateProgress(value: value)
            } else {
                guard try definition.isCompleted(value: command.value) else { throw DomainError.invalidGoal }
            }
            let occurred = NativeStorageEncoding.date(command.occurredAtMillis)
            let today = try CalendarPolicy.credit(now: occurred, zoneID: habit.zoneID)
            let yesterday = try today.date.adding(days: -1).description
            let previousKey = try NativeStorageEncoding.key(command.habitID, yesterday)
            let previousComplete = try row(ownerID: command.ownerID, category: "completion", keyID: previousKey) != nil
            let credit = try CalendarPolicy.credit(now: occurred, zoneID: habit.zoneID,
                workoutStartedAt: command.workoutStartedAtMillis.map(NativeStorageEncoding.date), previousComplete: previousComplete)
            let dateKey = try NativeStorageEncoding.key(command.habitID, credit.date.description)
            let keyID = kind == .completion ? dateKey : command.recordID
            let result: NativeEntry
            if kind == .completion, let existing = try row(ownerID: command.ownerID, category: "completion", keyID: keyID) {
                result = try decode(NativeEntry.self, existing)
            } else {
                guard try entryRow(ownerID: command.ownerID, category: kind.rawValue, identifier: command.recordID) == nil else {
                    throw NativeStorageError.duplicateEntity
                }
                result = NativeEntry(ownerID: command.ownerID, id: command.recordID, habitID: command.habitID, kind: kind,
                    occurredAtMillis: command.occurredAtMillis, creditedDate: credit.date.description, zoneID: credit.zoneID,
                    creditReason: credit.reason, value: command.value)
                try append(ownerID: command.ownerID, category: kind.rawValue, identifier: result.id, keyID: keyID, value: result)
                try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: eventKind, entityID: result.id,
                    payload: try NativeStorageEncoding.encode(result), createdAtMillis: command.occurredAtMillis))
            }
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: eventKind,
                                            request: request, resultID: result.id))
            return result
        }
    }

    private func mutate<Result>(_ body: () throws -> Result) throws -> Result {
        modelContext.autosaveEnabled = false
        do {
            let result = try body()
            try modelContext.save()
            return result
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func row(ownerID: String, category: String, keyID: String) throws -> NativeLedgerRow? {
        let key = try NativeStorageEncoding.key(ownerID, category, keyID)
        var descriptor = FetchDescriptor<NativeLedgerRow>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func entryRow(ownerID: String, category: String, identifier: String) throws -> NativeLedgerRow? {
        var descriptor = FetchDescriptor<NativeLedgerRow>(predicate: #Predicate {
            $0.ownerID == ownerID && $0.category == category && $0.identifier == identifier
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func rows(ownerID: String, category: String) throws -> [NativeLedgerRow] {
        try modelContext.fetch(FetchDescriptor<NativeLedgerRow>(predicate: #Predicate {
            $0.ownerID == ownerID && $0.category == category
        }))
    }

    private func append<Value: Encodable>(ownerID: String, category: String, identifier: String, keyID: String, value: Value) throws {
        guard try row(ownerID: ownerID, category: category, keyID: keyID) == nil else { throw NativeStorageError.duplicateEntity }
        modelContext.insert(NativeLedgerRow(key: try NativeStorageEncoding.key(ownerID, category, keyID), ownerID: ownerID,
                                           category: category, identifier: identifier, payload: try NativeStorageEncoding.encode(value)))
    }

    private func appendEvent(_ event: NativeEvent) throws {
        try append(ownerID: event.ownerID, category: "event", identifier: event.eventID, keyID: event.eventID, value: event)
    }

    private func appendReceipt(_ receipt: NativeReceipt) throws {
        try append(ownerID: receipt.ownerID, category: "receipt", identifier: receipt.operationID, keyID: receipt.operationID, value: receipt)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ row: NativeLedgerRow) throws -> Value {
        try JSONDecoder().decode(type, from: row.payload)
    }
}