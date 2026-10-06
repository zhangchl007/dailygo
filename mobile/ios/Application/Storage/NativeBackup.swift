import Foundation
import DailyGoDomain

struct NativeBackup: Codable, Sendable {
    var format = "dailygo.ios.backup"
    var version = 3
    let ownerID: String
    let habits: [NativeHabit]
    let entries: [NativeEntry]
    let events: [NativeEvent]
    let receipts: [NativeReceipt]
    var deletedHabits: [NativeHabitDeletion]? = nil
    var completionStates: [NativeCompletionState]? = nil

    func validate(ownerID expectedOwner: String) throws {
        try NativeStorageEncoding.validateIdentity(expectedOwner)
          guard format == "dailygo.ios.backup", (1...3).contains(version), ownerID == expectedOwner,
              version != 1 || deletedHabits == nil,
              version == 3 || completionStates == nil else { throw NativeStorageError.invalidDefinition }
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
        try identities((deletedHabits ?? []).map { ($0.ownerID, $0.habitID) })
        try identities((completionStates ?? []).map { ($0.ownerID, $0.recordID) })
        let definitions = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        let deletions = Dictionary(uniqueKeysWithValues: (deletedHabits ?? []).map { ($0.habitID, $0) })
        guard Set(definitions.keys).isDisjoint(with: deletions.keys) else { throw NativeStorageError.invalidDefinition }
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
        for state in completionStates ?? [] {
            guard let receipt = operations[state.operationID], receipt.kind == "checkin.corrected", receipt.resultID == state.recordID else { throw NativeStorageError.invalidDefinition }
            let request = try NativeStorageEncoding.decode(NativeCompletionCorrectionCommand.self, from: receipt.request)
            guard request.ownerID == state.ownerID, request.recordID == state.recordID, request.operationID == state.operationID,
                  request.active == state.active, request.occurredAtMillis == state.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
        }
        for deletion in deletions.values {
            try NativeStorageEncoding.validateIdentity(deletion.operationID)
            guard let receipt = operations[deletion.operationID], receipt.kind == "habit.deleted",
                  receipt.resultID == deletion.habitID else { throw NativeStorageError.invalidDefinition }
        }
        for receipt in receipts {
            if receipt.kind == "checkin.corrected" {
                let request = try NativeStorageEncoding.decode(NativeCompletionCorrectionCommand.self, from: receipt.request)
                try request.validate()
                guard request.ownerID == ownerID, request.operationID == receipt.operationID, request.recordID == receipt.resultID,
                      let entry = entries.first(where: { $0.kind == .completion && $0.id == request.recordID }),
                      request.occurredAtMillis >= entry.occurredAtMillis, request.asOfMillis == nil,
                      receipt.resultKey == nil || receipt.resultKey == request.recordID,
                      (completionStates ?? []).contains(where: { $0.recordID == request.recordID && $0.occurredAtMillis >= request.occurredAtMillis }) else { throw NativeStorageError.invalidDefinition }
            } else if receipt.kind == "habit.retired" {
                let request = try NativeStorageEncoding.decode(NativeRetiredHabitOperation.self, from: receipt.request)
                try NativeStorageEncoding.validateIdentity(request.ownerID, request.operationID, request.habitID)
                guard request.ownerID == ownerID, request.operationID == receipt.operationID, request.habitID == receipt.resultID,
                      deletions[request.habitID] != nil, receipt.resultKey == nil || receipt.resultKey == request.habitID else { throw NativeStorageError.invalidDefinition }
            } else if receipt.kind == "habit.deleted" {
                let request = try NativeStorageEncoding.decode(NativeHabitDeleteCommand.self, from: receipt.request)
                try request.validate()
                guard request.ownerID == ownerID, request.operationID == receipt.operationID, request.habitID == receipt.resultID,
                      let deletion = deletions[request.habitID], deletion.operationID == request.operationID,
                      deletion.occurredAtMillis == request.occurredAtMillis, request.asOfMillis == nil,
                      receipt.resultKey == nil || receipt.resultKey == request.habitID else { throw NativeStorageError.invalidDefinition }
            } else if receipt.kind == "habit.created" {
                let request = try NativeStorageEncoding.decode(NativeHabit.self, from: receipt.request)
                _ = try request.definition()
                guard request.ownerID == ownerID, request.id == receipt.resultID, definitions[request.id] != nil else { throw NativeStorageError.invalidDefinition }
                guard receipt.resultKey == nil || receipt.resultKey == request.id else { throw NativeStorageError.invalidDefinition }
            } else if receipt.kind == "habit.edited" {
                let request = try NativeStorageEncoding.decode(NativeHabitEditCommand.self, from: receipt.request)
                guard request.ownerID == ownerID, request.operationID == receipt.operationID, request.habitID == receipt.resultID,
                      let habit = definitions[request.habitID], request.asOfMillis == nil,
                      receipt.resultKey == nil || receipt.resultKey == request.habitID else { throw NativeStorageError.invalidDefinition }
                _ = try request.applying(to: habit)
            } else if receipt.kind == "habit.archived" || receipt.kind == "habit.restored" {
                let request = try NativeStorageEncoding.decode(NativeHabitArchiveCommand.self, from: receipt.request)
                try request.validate()
                guard request.ownerID == ownerID, request.operationID == receipt.operationID, request.habitID == receipt.resultID,
                      let habit = definitions[request.habitID], request.occurredAtMillis >= habit.createdAtMillis,
                      request.asOfMillis == nil, request.archived == (receipt.kind == "habit.archived"),
                      receipt.resultKey == nil || receipt.resultKey == request.habitID else { throw NativeStorageError.invalidDefinition }
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
            guard event.kind != "habit.retired" else { throw NativeStorageError.invalidDefinition }
            if event.kind == "checkin.corrected" {
                let payload = try NativeStorageEncoding.decode(NativeCompletionCorrectionCommand.self, from: event.payload)
                let request = try NativeStorageEncoding.decode(NativeCompletionCorrectionCommand.self, from: receipt.request)
                guard payload == request, event.createdAtMillis == request.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
            } else if event.kind == "habit.deleted" {
                let payload = try NativeStorageEncoding.decode(NativeHabitDeleteCommand.self, from: event.payload)
                let request = try NativeStorageEncoding.decode(NativeHabitDeleteCommand.self, from: receipt.request)
                guard payload == request, event.createdAtMillis == request.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
            } else if event.kind == "habit.created" {
                let payload = try NativeStorageEncoding.decode(NativeHabit.self, from: event.payload)
                let original = try NativeStorageEncoding.decode(NativeHabit.self, from: receipt.request)
                guard original == payload else { throw NativeStorageError.invalidDefinition }
            } else if event.kind == "habit.edited" {
                let payload = try NativeStorageEncoding.decode(NativeHabitEditCommand.self, from: event.payload)
                let request = try NativeStorageEncoding.decode(NativeHabitEditCommand.self, from: receipt.request)
                guard payload == request, event.createdAtMillis == request.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
            } else if event.kind == "habit.archived" || event.kind == "habit.restored" {
                let payload = try NativeStorageEncoding.decode(NativeHabitArchiveCommand.self, from: event.payload)
                let request = try NativeStorageEncoding.decode(NativeHabitArchiveCommand.self, from: receipt.request)
                guard payload == request, event.createdAtMillis == request.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
            } else {
                let payload = try NativeStorageEncoding.decode(NativeEntry.self, from: event.payload)
                let kind: NativeEntryKind = event.kind == "progress.recorded" ? .progress : .completion
                guard payload.kind == kind, entries.contains(payload), payload.id == event.entityID else { throw NativeStorageError.invalidDefinition }
            }
        }
    }
}