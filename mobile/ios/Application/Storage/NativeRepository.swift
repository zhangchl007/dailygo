import Foundation
import SwiftData
import DailyGoDomain

@ModelActor
actor NativeRepository {
    private var activeContext: ModelContext?

    private var ledgerContext: ModelContext {
        if let activeContext { return activeContext }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        activeContext = context
        return context
    }

    func importLegacy(url: URL, ownerID: String, zones: [String: String], acceptUnverified: Bool) throws -> NativeLegacyReport {
        let candidate: (NativeBackup?, [NativeLegacyIssue])
        do { candidate = try NativeLegacy.read(url: url, ownerID: ownerID, zones: zones, acceptUnverified: acceptUnverified) }
        catch { return NativeLegacyReport(imported: false, issues: [NativeLegacyIssue(entityID: nil, code: "INVALID_LEGACY_SOURCE")]) }
        guard let backup = candidate.0 else { return NativeLegacyReport(imported: false, issues: candidate.1) }
        do { try importOwner(ownerID: ownerID, contents: NativeStorageEncoding.encode(backup)) }
        catch NativeStorageError.operationConflict {
            return NativeLegacyReport(imported: false, issues: candidate.1 + [NativeLegacyIssue(entityID: nil, code: "TARGET_CONFLICT")])
        }
        return NativeLegacyReport(imported: true, issues: candidate.1)
    }

    func exportOwner(ownerID: String) throws -> Data {
        try requireActive(ownerID: ownerID)
        let entries = try rows(ownerID: ownerID, category: "completion").map { try decode(NativeEntry.self, $0) } +
            rows(ownerID: ownerID, category: "progress").map { try decode(NativeEntry.self, $0) }
        let backup = NativeBackup(ownerID: ownerID, habits: try habits(ownerID: ownerID),
            entries: entries.sorted { ($0.kind.rawValue, $0.id) < ($1.kind.rawValue, $1.id) }, events: try events(ownerID: ownerID),
            receipts: try rows(ownerID: ownerID, category: "receipt").map { try decode(NativeReceipt.self, $0) }.sorted { $0.operationID < $1.operationID },
            deletedHabits: try rows(ownerID: ownerID, category: "deletedHabit").map { try decode(NativeHabitDeletion.self, $0) }.sorted { $0.habitID < $1.habitID },
            completionStates: try rows(ownerID: ownerID, category: "completionState").map { try decode(NativeCompletionState.self, $0) }.sorted { $0.recordID < $1.recordID })
        try backup.validate(ownerID: ownerID)
        let contents = try NativeStorageEncoding.encode(backup)
        guard contents.count <= 32 * 1024 * 1024 else { throw NativeStorageError.invalidDefinition }
        return contents
    }

    func importOwner(ownerID: String, contents: Data) throws {
        guard contents.count <= 32 * 1024 * 1024 else { throw NativeStorageError.invalidDefinition }
        let backup = try NativeStorageEncoding.decode(NativeBackup.self, from: contents)
        try backup.validate(ownerID: ownerID)
        try mutate {
            try requireActive(ownerID: ownerID)
            for habit in backup.habits {
                guard try row(ownerID: ownerID, category: "deletedHabit", keyID: habit.id) == nil else { throw NativeStorageError.operationConflict }
                try merge(ownerID: ownerID, category: "habit", identifier: habit.id, keyID: habit.id, value: habit)
            }
            for deletion in backup.deletedHabits ?? [] {
                guard try row(ownerID: ownerID, category: "habit", keyID: deletion.habitID) == nil else { throw NativeStorageError.operationConflict }
                try merge(ownerID: ownerID, category: "deletedHabit", identifier: deletion.habitID, keyID: deletion.habitID, value: deletion)
            }
            for entry in backup.entries {
                let keyID = entry.kind == .completion ? try NativeStorageEncoding.key(entry.habitID, entry.creditedDate) : entry.id
                if let existing = try entryRow(ownerID: ownerID, category: entry.kind.rawValue, identifier: entry.id) {
                    guard try decode(NativeEntry.self, existing) == entry else { throw NativeStorageError.operationConflict }
                }
                try merge(ownerID: ownerID, category: entry.kind.rawValue, identifier: entry.id, keyID: keyID, value: entry)
            }
            for event in backup.events {
                if try row(ownerID: ownerID, category: "event", keyID: event.eventID) != nil || receipt(ownerID: ownerID, operationID: event.eventID) == nil {
                    try merge(ownerID: ownerID, category: "event", identifier: event.eventID, keyID: event.eventID, value: event)
                }
            }
            for state in backup.completionStates ?? [] {
                try merge(ownerID: ownerID, category: "completionState", identifier: state.recordID, keyID: state.recordID, value: state)
            }
            for receipt in backup.receipts { try merge(ownerID: ownerID, category: "receipt", identifier: receipt.operationID, keyID: receipt.operationID, value: receipt) }
        }
    }

    func deleteOwner(ownerID: String) throws {
        try NativeStorageEncoding.validateIdentity(ownerID)
        try mutate {
            if try row(ownerID: ownerID, category: "deleted", keyID: ownerID) != nil { return }
            let descriptor = FetchDescriptor<NativeLedgerRow>(predicate: #Predicate { $0.ownerID == ownerID })
            for record in try ledgerContext.fetch(descriptor) { ledgerContext.delete(record) }
            let scopes = FetchDescriptor<NativeScopeRow>(predicate: #Predicate { $0.ownerID == ownerID })
            for scope in try ledgerContext.fetch(scopes) { ledgerContext.delete(scope) }
            try append(ownerID: ownerID, category: "deleted", identifier: ownerID, keyID: ownerID, value: ["deleted": true])
        }
    }

    private func requireActive(ownerID: String) throws {
        try NativeStorageEncoding.validateIdentity(ownerID)
        guard try row(ownerID: ownerID, category: "deleted", keyID: ownerID) == nil else { throw NativeStorageError.deletedOwner }
    }

    private func merge<Value: Encodable>(ownerID: String, category: String, identifier: String, keyID: String, value: Value) throws {
        if let existing = try row(ownerID: ownerID, category: category, keyID: keyID) {
            guard existing.payload == (try NativeStorageEncoding.encode(value)) else { throw NativeStorageError.operationConflict }
        } else {
            try append(ownerID: ownerID, category: category, identifier: identifier, keyID: keyID, value: value)
        }
    }

    func saveHabit(_ habit: NativeHabit, operationID: String) throws -> NativeHabit {
        try NativeStorageEncoding.validateIdentity(habit.ownerID, habit.id, operationID)
        _ = try habit.definition()
        let request = try NativeStorageEncoding.encode(habit)
        return try mutate {
            try requireActive(ownerID: habit.ownerID)
            guard try row(ownerID: habit.ownerID, category: "deletedHabit", keyID: habit.id) == nil else { throw NativeStorageError.missingHabit }
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

    func deleteHabit(_ command: NativeHabitDeleteCommand) throws {
        try command.validate()
        let request = try command.request()
        try mutate {
            try requireActive(ownerID: command.ownerID)
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == "habit.deleted", previous.request == request,
                      try row(ownerID: command.ownerID, category: "deletedHabit", keyID: command.habitID) != nil else { throw NativeStorageError.operationConflict }
                return
            }
            guard let habitRow = try row(ownerID: command.ownerID, category: "habit", keyID: command.habitID) else { throw NativeStorageError.missingHabit }
            let habit = try decode(NativeHabit.self, habitRow)
            guard command.occurredAtMillis >= habit.createdAtMillis else { throw NativeStorageError.invalidDefinition }
            let completions = try scopeRows(ownerID: command.ownerID, category: "completion", habitID: command.habitID)
            let progress = try scopeRows(ownerID: command.ownerID, category: "progress", habitID: command.habitID)
            let completionIDs = Set(completions.map(\.identifier))
            let progressIDs = Set(progress.map(\.identifier))
            for record in try rows(ownerID: command.ownerID, category: "receipt") {
                let receipt = try decode(NativeReceipt.self, record)
                let related = receipt.kind.hasPrefix("habit.") ? receipt.resultID == command.habitID :
                    (receipt.kind == "checkin.completed" || receipt.kind == "checkin.corrected") ? completionIDs.contains(receipt.resultID) :
                    receipt.kind == "progress.recorded" && progressIDs.contains(receipt.resultID)
                if related {
                    if let event = try row(ownerID: command.ownerID, category: "event", keyID: receipt.operationID) { ledgerContext.delete(event) }
                    let retired = NativeRetiredHabitOperation(ownerID: command.ownerID, operationID: receipt.operationID, habitID: command.habitID)
                    record.payload = try NativeStorageEncoding.encode(NativeReceipt(ownerID: command.ownerID, operationID: receipt.operationID,
                        kind: "habit.retired", request: NativeStorageEncoding.encode(retired), resultID: command.habitID, resultKey: command.habitID))
                }
            }
            for entry in completions {
                if let state = try row(ownerID: command.ownerID, category: "completionState", keyID: entry.identifier) { ledgerContext.delete(state) }
            }
            for entry in completions + progress { ledgerContext.delete(entry) }
            for category in ["completion", "progress"] {
                let key = try NativeStorageEncoding.key(command.ownerID, category, command.habitID)
                let descriptor = FetchDescriptor<NativeScopeRow>(predicate: #Predicate { $0.key == key })
                for scope in try ledgerContext.fetch(descriptor) { ledgerContext.delete(scope) }
            }
            ledgerContext.delete(habitRow)
            let deletion = NativeHabitDeletion(ownerID: command.ownerID, habitID: command.habitID,
                operationID: command.operationID, occurredAtMillis: command.occurredAtMillis)
            try append(ownerID: command.ownerID, category: "deletedHabit", identifier: command.habitID, keyID: command.habitID, value: deletion)
            try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: "habit.deleted",
                entityID: command.habitID, payload: request, createdAtMillis: command.occurredAtMillis))
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: "habit.deleted",
                request: request, resultID: command.habitID, resultKey: command.habitID))
        }
    }

    func editHabit(_ command: NativeHabitEditCommand) throws -> NativeHabit {
        try command.validate()
        let request = try command.request()
        return try mutate {
            try requireActive(ownerID: command.ownerID)
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == "habit.edited", previous.request == request else { throw NativeStorageError.operationConflict }
                guard let result = try row(ownerID: command.ownerID, category: "habit", keyID: previous.resultID) else { throw NativeStorageError.missingResult }
                return try decode(NativeHabit.self, result)
            }
            guard let record = try row(ownerID: command.ownerID, category: "habit", keyID: command.habitID) else { throw NativeStorageError.missingHabit }
            let updated = try command.applying(to: decode(NativeHabit.self, record))
            record.payload = try NativeStorageEncoding.encode(updated)
            try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: "habit.edited",
                entityID: command.habitID, payload: request, createdAtMillis: command.occurredAtMillis))
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: "habit.edited",
                request: request, resultID: command.habitID, resultKey: command.habitID))
            return updated
        }
    }

    func setHabitGoal(_ command: NativeHabitGoalCommand) throws -> NativeHabit {
        try command.validate()
        let request = try command.request()
        return try mutate {
            try requireActive(ownerID: command.ownerID)
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == "habit.goal_changed", previous.request == request else { throw NativeStorageError.operationConflict }
                guard let result = try row(ownerID: command.ownerID, category: "habit", keyID: previous.resultID) else { throw NativeStorageError.missingResult }
                return try decode(NativeHabit.self, result)
            }
            guard let record = try row(ownerID: command.ownerID, category: "habit", keyID: command.habitID) else { throw NativeStorageError.missingHabit }
            for category in ["completion", "progress"] {
                let ownerID = command.ownerID
                let scopeKey = try NativeStorageEncoding.key(ownerID, category, command.habitID)
                var descriptor = FetchDescriptor<NativeLedgerRow>(predicate: #Predicate {
                    $0.ownerID == ownerID && $0.category == category && $0.habitScope?.key == scopeKey
                })
                descriptor.fetchLimit = 1
                guard try ledgerContext.fetch(descriptor).isEmpty else { throw NativeStorageError.invalidDefinition }
            }
            let updated = try command.applying(to: decode(NativeHabit.self, record))
            record.payload = try NativeStorageEncoding.encode(updated)
            try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: "habit.goal_changed",
                entityID: command.habitID, payload: request, createdAtMillis: command.occurredAtMillis))
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: "habit.goal_changed",
                request: request, resultID: command.habitID, resultKey: command.habitID))
            return updated
        }
    }

    func setHabitArchived(_ command: NativeHabitArchiveCommand) throws -> NativeHabit {
        try command.validate()
        let kind = command.archived ? "habit.archived" : "habit.restored"
        let request = try command.request()
        return try mutate {
            try requireActive(ownerID: command.ownerID)
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == kind, previous.request == request else { throw NativeStorageError.operationConflict }
                guard let result = try row(ownerID: command.ownerID, category: "habit", keyID: previous.resultID) else { throw NativeStorageError.missingResult }
                return try decode(NativeHabit.self, result)
            }
            guard let record = try row(ownerID: command.ownerID, category: "habit", keyID: command.habitID) else { throw NativeStorageError.missingHabit }
            let habit = try decode(NativeHabit.self, record)
            guard command.occurredAtMillis >= habit.createdAtMillis else { throw NativeStorageError.invalidDefinition }
            let updated = NativeHabit(ownerID: habit.ownerID, id: habit.id, title: habit.title,
                scheduleKind: habit.scheduleKind, scheduleParameter: habit.scheduleParameter, goalKind: habit.goalKind,
                target: habit.target, zoneID: habit.zoneID, createdAtMillis: habit.createdAtMillis, archived: command.archived)
            record.payload = try NativeStorageEncoding.encode(updated)
            try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: kind,
                entityID: command.habitID, payload: request, createdAtMillis: command.occurredAtMillis))
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: kind,
                request: request, resultID: command.habitID, resultKey: command.habitID))
            return updated
        }
    }

    func recordProgress(_ command: NativeEntryCommand) throws -> NativeEntry { try writeEntry(command, kind: .progress) }
    func complete(_ command: NativeEntryCommand) throws -> NativeEntry { try writeEntry(command, kind: .completion) }

    func correctCompletion(_ command: NativeCompletionCorrectionCommand) throws -> NativeCompletionState {
        try command.validate()
        let request = try command.request()
        return try mutate {
            try requireActive(ownerID: command.ownerID)
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == "checkin.corrected", previous.request == request,
                      let state = try row(ownerID: command.ownerID, category: "completionState", keyID: previous.resultID) else { throw NativeStorageError.operationConflict }
                return try decode(NativeCompletionState.self, state)
            }
            guard let record = try entryRow(ownerID: command.ownerID, category: "completion", identifier: command.recordID) else { throw NativeStorageError.missingResult }
            let entry = try decode(NativeEntry.self, record)
            guard let habitRow = try row(ownerID: command.ownerID, category: "habit", keyID: entry.habitID) else { throw NativeStorageError.missingHabit }
            let habit = try decode(NativeHabit.self, habitRow)
            guard (!command.active || !habit.archived), command.occurredAtMillis >= entry.occurredAtMillis else { throw NativeStorageError.invalidDefinition }
            let existing = try row(ownerID: command.ownerID, category: "completionState", keyID: command.recordID)
            if let existing {
                guard command.occurredAtMillis >= (try decode(NativeCompletionState.self, existing)).occurredAtMillis else { throw NativeStorageError.operationConflict }
            }
            let state = NativeCompletionState(ownerID: command.ownerID, recordID: command.recordID, active: command.active,
                operationID: command.operationID, occurredAtMillis: command.occurredAtMillis)
            if let existing { existing.payload = try NativeStorageEncoding.encode(state) }
            else { try append(ownerID: command.ownerID, category: "completionState", identifier: command.recordID, keyID: command.recordID, value: state) }
            try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: "checkin.corrected",
                entityID: command.recordID, payload: request, createdAtMillis: command.occurredAtMillis))
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: "checkin.corrected",
                request: request, resultID: command.recordID, resultKey: command.recordID))
            return state
        }
    }

    private func completionIsActive(ownerID: String, recordID: String) throws -> Bool {
        guard let state = try row(ownerID: ownerID, category: "completionState", keyID: recordID) else { return true }
        return try decode(NativeCompletionState.self, state).active
    }

    func completionOn(ownerID: String, habitID: String, date: String) throws -> NativeEntry? {
        guard let entry = try completionRecordOn(ownerID: ownerID, habitID: habitID, date: date),
              try completionIsActive(ownerID: ownerID, recordID: entry.id) else { return nil }
        return entry
    }

    func completionRecordOn(ownerID: String, habitID: String, date: String) throws -> NativeEntry? {
        try NativeStorageEncoding.validateIdentity(ownerID, habitID)
        _ = try LocalDay(date)
        let key = try NativeStorageEncoding.key(habitID, date)
        guard let record = try row(ownerID: ownerID, category: "completion", keyID: key) else { return nil }
        return try decode(NativeEntry.self, record)
    }

    func entries(ownerID: String, habitID: String, kind: NativeEntryKind) throws -> [NativeEntry] {
        try NativeStorageEncoding.validateIdentity(ownerID, habitID)
        return try scopeRows(ownerID: ownerID, category: kind.rawValue, habitID: habitID).map { try decode(NativeEntry.self, $0) }
            .filter { entry in
                if kind != .completion { return true }
                return try completionIsActive(ownerID: ownerID, recordID: entry.id)
            }
            .sorted { ($0.creditedDate, $0.occurredAtMillis, $0.id) < ($1.creditedDate, $1.occurredAtMillis, $1.id) }
    }

    func recentCompletions(ownerID: String, habitID: String, through date: String, days: Int = 35) throws -> [NativeEntry] {
        try NativeStorageEncoding.validateIdentity(ownerID, habitID)
        guard (1...366).contains(days) else { throw NativeStorageError.invalidDefinition }
        let end = try LocalDay(date)
        return try (0..<days).compactMap { offset in
            let day = try end.adding(days: offset - days + 1)
            return try completionOn(ownerID: ownerID, habitID: habitID, date: day.description)
        }
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
            if let event = try row(ownerID: ownerID, category: "event", keyID: eventID) { ledgerContext.delete(event) }
        }
    }

    private func writeEntry(_ command: NativeEntryCommand, kind: NativeEntryKind) throws -> NativeEntry {
        try command.validate()
        let request = try command.request()
        let eventKind = kind == .completion ? "checkin.completed" : "progress.recorded"
        return try mutate {
            try requireActive(ownerID: command.ownerID)
            if let previous = try receipt(ownerID: command.ownerID, operationID: command.operationID) {
                guard previous.kind == eventKind, previous.request == request else { throw NativeStorageError.operationConflict }
                let existing: NativeLedgerRow?
                if let key = previous.resultKey { existing = try row(ownerID: command.ownerID, category: kind.rawValue, keyID: key) }
                else { existing = try entryRow(ownerID: command.ownerID, category: kind.rawValue, identifier: previous.resultID) }
                guard let row = existing else {
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
            var original: NativeEntry?
            if let identifier = command.correctsRecordID {
                try NativeStorageEncoding.validateIdentity(identifier)
                guard kind == .progress, command.workoutStartedAtMillis == nil,
                      let record = try row(ownerID: command.ownerID, category: "progress", keyID: identifier) else {
                    throw NativeStorageError.invalidDefinition
                }
                let entry = try decode(NativeEntry.self, record)
                guard entry.habitID == command.habitID, command.occurredAtMillis >= entry.occurredAtMillis else {
                    throw NativeStorageError.invalidDefinition
                }
                original = entry
            }
            let occurred = NativeStorageEncoding.date(command.occurredAtMillis)
            let today = try CalendarPolicy.credit(now: occurred, zoneID: habit.zoneID)
            let yesterday = try today.date.adding(days: -1).description
            let previousComplete = try completionOn(ownerID: command.ownerID, habitID: command.habitID, date: yesterday) != nil
            let credit = try CalendarPolicy.credit(now: occurred, zoneID: habit.zoneID,
                workoutStartedAt: command.workoutStartedAtMillis.map(NativeStorageEncoding.date), previousComplete: previousComplete)
            let dateKey = try NativeStorageEncoding.key(command.habitID, credit.date.description)
            let keyID = kind == .completion ? dateKey : command.recordID
            let result: NativeEntry
            if kind == .completion, let existing = try row(ownerID: command.ownerID, category: "completion", keyID: keyID) {
                result = try decode(NativeEntry.self, existing)
                guard try completionIsActive(ownerID: command.ownerID, recordID: result.id) else { throw NativeStorageError.operationConflict }
            } else {
                guard try entryRow(ownerID: command.ownerID, category: kind.rawValue, identifier: command.recordID) == nil else {
                    throw NativeStorageError.duplicateEntity
                }
                result = NativeEntry(ownerID: command.ownerID, id: command.recordID, habitID: command.habitID, kind: kind,
                    occurredAtMillis: command.occurredAtMillis, creditedDate: original?.creditedDate ?? credit.date.description,
                    zoneID: original?.zoneID ?? credit.zoneID, creditReason: original?.creditReason ?? credit.reason, value: command.value)
                try append(ownerID: command.ownerID, category: kind.rawValue, identifier: result.id, keyID: keyID, value: result)
                try appendEvent(NativeEvent(ownerID: command.ownerID, eventID: command.operationID, kind: eventKind, entityID: result.id,
                    payload: try NativeStorageEncoding.encode(result), createdAtMillis: command.occurredAtMillis))
            }
            try appendReceipt(NativeReceipt(ownerID: command.ownerID, operationID: command.operationID, kind: eventKind,
                                            request: request, resultID: result.id, resultKey: keyID))
            return result
        }
    }

    private func mutate<Result>(_ body: () throws -> Result) throws -> Result {
        do {
            let result = try body()
            try ledgerContext.save()
            return result
        } catch {
            activeContext = nil
            throw error
        }
    }

    private func row(ownerID: String, category: String, keyID: String) throws -> NativeLedgerRow? {
        let key = try NativeStorageEncoding.key(ownerID, category, keyID)
        var descriptor = FetchDescriptor<NativeLedgerRow>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try ledgerContext.fetch(descriptor).first
    }

    private func entryRow(ownerID: String, category: String, identifier: String) throws -> NativeLedgerRow? {
        try rows(ownerID: ownerID, category: category).first { $0.identifier == identifier }
    }

    private func rows(ownerID: String, category: String) throws -> [NativeLedgerRow] {
        try scopeRows(ownerID: ownerID, category: category)
    }

    private func scopeRows(ownerID: String, category: String, habitID: String = "") throws -> [NativeLedgerRow] {
        let key = try NativeStorageEncoding.key(ownerID, category, habitID)
        var descriptor = FetchDescriptor<NativeScopeRow>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        guard let scope = try ledgerContext.fetch(descriptor).first else { return [] }
        return habitID.isEmpty ? scope.records : scope.entries
    }

    private func append<Value: Encodable>(ownerID: String, category: String, identifier: String, keyID: String, value: Value) throws {
        guard try row(ownerID: ownerID, category: category, keyID: keyID) == nil else { throw NativeStorageError.duplicateEntity }
        let record = NativeLedgerRow(key: try NativeStorageEncoding.key(ownerID, category, keyID), ownerID: ownerID,
                        category: category, identifier: identifier, payload: try NativeStorageEncoding.encode(value))
        ledgerContext.insert(record)
        try NativeIndexes.attach(record, context: ledgerContext)
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