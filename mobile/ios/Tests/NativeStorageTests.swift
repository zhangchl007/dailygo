import Foundation
import DailyGoDomain
import SwiftData
import SQLite3
import XCTest
@testable import DailyGo

private enum UnsupportedNativeSchema: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(99, 0, 0) }
    static var models: [any PersistentModel.Type] { [UnknownRow.self] }
    @Model final class UnknownRow {
        var value: String
        init(value: String) { self.value = value }
    }
}

@MainActor
final class NativeStorageTests: XCTestCase {
    private let instant: Int64 = 1_791_282_600_000

    private func habit(ownerID: String = "guest", id: String = "walk", archived: Bool = false) -> NativeHabit {
        NativeHabit(ownerID: ownerID, id: id, title: "Walk", scheduleKind: "daily", scheduleParameter: nil,
                    goalKind: "steps", target: 1000, zoneID: "Asia/Shanghai", createdAtMillis: instant, archived: archived)
    }

    private func command(ownerID: String = "guest", operationID: String = "progress", recordID: String = "entry",
                         habitID: String = "walk", value: Double = 400, asOfMillis: Int64? = nil) -> NativeEntryCommand {
        NativeEntryCommand(ownerID: ownerID, operationID: operationID, recordID: recordID, habitID: habitID,
                           occurredAtMillis: instant, value: value, workoutStartedAtMillis: nil, asOfMillis: asOfMillis)
    }

    private func storeURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("test.store")
    }

    private func expectFailure(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected mutation failure")
        } catch {}
    }

    func testGoalChangesBeforeHistoryPreserveRetriesReopenAndBackup() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let change = NativeHabitGoalCommand(ownerID: "guest", operationID: "goal", habitID: "walk",
            goalKind: "steps", target: 2000, occurredAtMillis: instant + 1)
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            _ = try await repository.saveHabit(habit(ownerID: "other"), operationID: "create")
            let updated = try await repository.setHabitGoal(change)
            XCTAssertEqual(updated.target, 2000)
            _ = try await repository.recordProgress(command())
            try await repository.acknowledge(ownerID: "guest", eventID: "goal")
            let retried = try await repository.setHabitGoal(change)
            XCTAssertEqual(retried, updated)
            await expectFailure {
                _ = try await repository.setHabitGoal(NativeHabitGoalCommand(ownerID: "guest", operationID: "new-goal",
                    habitID: "walk", goalKind: "steps", target: 3000, occurredAtMillis: self.instant + 2))
            }
            let other = try await repository.habits(ownerID: "other")
            let rejected = try await repository.receipt(ownerID: "guest", operationID: "new-goal")
            XCTAssertEqual(other, [habit(ownerID: "other")])
            XCTAssertNil(rejected)
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let retried = try await repository.setHabitGoal(change)
        XCTAssertEqual(retried.target, 2000)
        let backup = try await repository.exportOwner(ownerID: "guest")
        let targetURL = try storeURL()
        defer { try? FileManager.default.removeItem(at: targetURL.deletingLastPathComponent()) }
        let target = NativeRepository(modelContainer: try NativeStore.open(url: targetURL))
        try await target.importOwner(ownerID: "guest", contents: backup)
        let restored = try await target.setHabitGoal(change)
        let progress = try await target.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        let events = try await target.events(ownerID: "guest")
        XCTAssertEqual(restored.target, 2000)
        XCTAssertEqual(progress.map(\.value), [400])
        XCTAssertFalse(events.contains { $0.eventID == "goal" })
    }

    func testNumericCorrectionsRetainOriginalValuesCreditAndRetries() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let correction = NativeEntryCommand(ownerID: "guest", operationID: "correction", recordID: "corrected",
            habitID: "walk", occurredAtMillis: instant + 2, value: 200, workoutStartedAtMillis: nil,
            asOfMillis: nil, correctsRecordID: "entry")
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            let original = try await repository.recordProgress(command())
            _ = try await repository.editHabit(NativeHabitEditCommand(ownerID: "guest", operationID: "timezone", habitID: "walk",
                title: "Walk", scheduleKind: "daily", scheduleParameter: nil, zoneID: "America/New_York", occurredAtMillis: instant + 1))
            let corrected = try await repository.recordProgress(correction)
            XCTAssertEqual(corrected.creditedDate, original.creditedDate)
            XCTAssertEqual(corrected.zoneID, original.zoneID)
            XCTAssertEqual(corrected.creditReason, original.creditReason)
            XCTAssertEqual(corrected.value, 200)
            try await repository.acknowledge(ownerID: "guest", eventID: "correction")
            let retried = try await repository.recordProgress(correction)
            XCTAssertEqual(retried, corrected)
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let backup = try await repository.exportOwner(ownerID: "guest")
        let targetURL = try storeURL()
        defer { try? FileManager.default.removeItem(at: targetURL.deletingLastPathComponent()) }
        let target = NativeRepository(modelContainer: try NativeStore.open(url: targetURL))
        try await target.importOwner(ownerID: "guest", contents: backup)
        let restored = try await target.recordProgress(correction)
        let values = try await target.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        let events = try await target.events(ownerID: "guest")
        XCTAssertEqual(restored.value, 200)
        XCTAssertEqual(values.map(\.value), [400, 200])
        XCTAssertFalse(events.contains { $0.eventID == "correction" })
    }

    func testRecentCompletionsAreCalendarBoundedOwnerScopedAndDurable() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let lastInstant = instant + 999 * 86_400_000
        let end = try CalendarPolicy.credit(now: NativeStorageEncoding.date(lastInstant), zoneID: "Asia/Shanghai").date
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            _ = try await repository.saveHabit(habit(ownerID: "other"), operationID: "create")
            for offset in 0..<1000 {
                let entry = NativeEntryCommand(ownerID: "guest", operationID: "complete-\(offset)", recordID: "entry-\(offset)",
                    habitID: "walk", occurredAtMillis: instant + Int64(offset) * 86_400_000,
                    value: 1000, workoutStartedAtMillis: nil, asOfMillis: lastInstant)
                _ = try await repository.complete(entry)
            }
            _ = try await repository.complete(command(ownerID: "other", value: 1000))
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let history = try await repository.recentCompletions(ownerID: "guest", habitID: "walk", through: end.description)
        XCTAssertEqual(history.count, 35)
        XCTAssertEqual(history.first?.creditedDate, try end.adding(days: -34).description)
        XCTAssertEqual(history.last?.creditedDate, end.description)
        XCTAssertEqual(history.map(\.id), (965..<1000).map { "entry-\($0)" })
        let all = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        XCTAssertEqual(all.count, 1000)
        let summary = try StreakCalculator.calculate(schedule: .daily, dates: all.map { try LocalDay($0.creditedDate) }, asOf: end)
        XCTAssertEqual(summary.current, 1000)
        let other = try await repository.recentCompletions(ownerID: "other", habitID: "walk", through: end.description)
        XCTAssertTrue(other.isEmpty)
        let future = try await repository.recentCompletions(ownerID: "guest", habitID: "walk", through: end.adding(days: 35).description)
        XCTAssertTrue(future.isEmpty)
        for limit in [0, 367] {
            await expectFailure {
                _ = try await repository.recentCompletions(ownerID: "guest", habitID: "walk", through: end.description, days: limit)
            }
        }
    }

    func testCompletionCorrectionPreservesCreditAcrossRetryReopenAndBackup() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let undo = NativeCompletionCorrectionCommand(ownerID: "guest", operationID: "undo", recordID: "done", active: false, occurredAtMillis: instant + 1)
        let restore = NativeCompletionCorrectionCommand(ownerID: "guest", operationID: "restore", recordID: "done", active: true, occurredAtMillis: instant + 2)
        let original: NativeEntry
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            original = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
            _ = try await repository.correctCompletion(undo)
            try await repository.acknowledge(ownerID: "guest", eventID: "undo")
            _ = try await repository.correctCompletion(undo)
            let history = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
            let events = try await repository.events(ownerID: "guest")
            XCTAssertTrue(history.isEmpty)
            XCTAssertFalse(events.contains { $0.eventID == "undo" })
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let retained = try await repository.completionRecordOn(ownerID: "guest", habitID: "walk", date: original.creditedDate)
        let current = try await repository.completionOn(ownerID: "guest", habitID: "walk", date: original.creditedDate)
        XCTAssertEqual(retained, original)
        XCTAssertNil(current)
        let backup = try await repository.exportOwner(ownerID: "guest")
        let targetURL = try storeURL()
        defer { try? FileManager.default.removeItem(at: targetURL.deletingLastPathComponent()) }
        let target = NativeRepository(modelContainer: try NativeStore.open(url: targetURL))
        try await target.importOwner(ownerID: "guest", contents: backup)
        let restoredHistory = try await target.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        XCTAssertTrue(restoredHistory.isEmpty)
        _ = try await target.correctCompletion(restore)
        _ = try await target.correctCompletion(undo)
        let restored = try await target.completionOn(ownerID: "guest", habitID: "walk", date: original.creditedDate)
        XCTAssertEqual(restored, original)
        _ = try await target.exportOwner(ownerID: "guest")
    }

    func testCompletionCorrectionFailureRollsBackAndDeletionRetiresReceipts() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try NativeStore.open(url: url)
        let repository = NativeRepository(modelContainer: container)
        _ = try await repository.saveHabit(habit(), operationID: "create")
        let original = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
        let undo = NativeCompletionCorrectionCommand(ownerID: "guest", operationID: "undo", recordID: "done", active: false, occurredAtMillis: instant + 1)
        await expectFailure { _ = try await repository.correctCompletion(NativeCompletionCorrectionCommand(ownerID: "other", operationID: "undo", recordID: "done", active: false, occurredAtMillis: self.instant + 1)) }
        await expectFailure { _ = try await repository.correctCompletion(NativeCompletionCorrectionCommand(ownerID: "guest", operationID: "future", recordID: "done", active: false, occurredAtMillis: self.instant + 1, asOfMillis: self.instant)) }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let conflict = NativeLedgerRow(key: try NativeStorageEncoding.key("guest", "event", "undo"), ownerID: "guest",
            category: "event", identifier: "undo", payload: Data("{}".utf8))
        context.insert(conflict)
        try NativeIndexes.attach(conflict, context: context)
        try context.save()
        await expectFailure { _ = try await repository.correctCompletion(undo) }
        let active = try await repository.completionOn(ownerID: "guest", habitID: "walk", date: original.creditedDate)
        let receipt = try await repository.receipt(ownerID: "guest", operationID: "undo")
        XCTAssertEqual(active, original)
        XCTAssertNil(receipt)
        try await repository.acknowledge(ownerID: "guest", eventID: "undo")
        let oldBackup = try await repository.exportOwner(ownerID: "guest")
        _ = try await repository.correctCompletion(undo)
        try await repository.importOwner(ownerID: "guest", contents: oldBackup)
        let history = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        XCTAssertTrue(history.isEmpty)
        try await repository.deleteHabit(NativeHabitDeleteCommand(ownerID: "guest", operationID: "delete", habitID: "walk", occurredAtMillis: instant + 2))
        let retired = try await repository.receipt(ownerID: "guest", operationID: "undo")
        XCTAssertEqual(retired?.kind, "habit.retired")
        _ = try await repository.exportOwner(ownerID: "guest")
    }

    func testSingleHabitDeletionPreservesNamespacesAndFencesRestoration() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let deletion = NativeHabitDeleteCommand(ownerID: "guest", operationID: "delete", habitID: "walk", occurredAtMillis: instant + 1)
        let oldBackup: Data
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            _ = try await repository.saveHabit(habit(ownerID: "other"), operationID: "create")
            _ = try await repository.saveHabit(habit(id: "run"), operationID: "create-run")
            _ = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
            _ = try await repository.complete(command(operationID: "complete-run", recordID: "walk", habitID: "run", value: 1000))
            oldBackup = try await repository.exportOwner(ownerID: "guest")
            try await repository.deleteHabit(deletion)
            try await repository.deleteHabit(deletion)
            let habits = try await repository.habits(ownerID: "guest")
            let history = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
            let otherHistory = try await repository.entries(ownerID: "guest", habitID: "run", kind: .completion)
            let otherOwner = try await repository.habits(ownerID: "other")
            let events = try await repository.events(ownerID: "guest")
            XCTAssertEqual(habits.map(\.id), ["run"])
            XCTAssertTrue(history.isEmpty)
            XCTAssertEqual(otherHistory[0].id, "walk")
            XCTAssertEqual(otherOwner, [habit(ownerID: "other")])
            XCTAssertEqual(Set(events.map(\.eventID)), Set(["create-run", "complete-run", "delete"]))
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        try await repository.acknowledge(ownerID: "guest", eventID: "delete")
        try await repository.deleteHabit(deletion)
        await expectFailure { _ = try await repository.saveHabit(self.habit(), operationID: "new") }
        await expectFailure { _ = try await repository.saveHabit(self.habit(id: "fresh"), operationID: "create") }
        let retired = try await repository.receipt(ownerID: "guest", operationID: "create")
        XCTAssertEqual(retired?.kind, "habit.retired")
        XCTAssertFalse(String(data: retired!.request, encoding: .utf8)!.contains("Asia/Shanghai"))
        XCTAssertFalse(String(data: retired!.request, encoding: .utf8)!.contains("Walk"))
        await expectFailure { try await repository.importOwner(ownerID: "guest", contents: oldBackup) }
        let targetURL = try storeURL()
        defer { try? FileManager.default.removeItem(at: targetURL.deletingLastPathComponent()) }
        let target = NativeRepository(modelContainer: try NativeStore.open(url: targetURL))
        let backup = try await repository.exportOwner(ownerID: "guest")
        try await target.importOwner(ownerID: "guest", contents: backup)
        try await target.deleteHabit(deletion)
        await expectFailure { try await target.importOwner(ownerID: "guest", contents: oldBackup) }
        await expectFailure { _ = try await target.saveHabit(self.habit(), operationID: "new") }
        let events = try await target.events(ownerID: "guest")
        XCTAssertFalse(events.contains { $0.eventID == "delete" })
    }

    func testSingleHabitDeletionFailurePreservesHistoryAndRetryState() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try NativeStore.open(url: url)
        let repository = NativeRepository(modelContainer: container)
        _ = try await repository.saveHabit(habit(), operationID: "create")
        let entry = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
        let deletion = NativeHabitDeleteCommand(ownerID: "guest", operationID: "delete", habitID: "walk", occurredAtMillis: instant + 1)
        for invalid in [
            NativeHabitDeleteCommand(ownerID: "other", operationID: "delete", habitID: "walk", occurredAtMillis: instant + 1),
            NativeHabitDeleteCommand(ownerID: "guest", operationID: "delete", habitID: "walk", occurredAtMillis: instant - 1),
            NativeHabitDeleteCommand(ownerID: "guest", operationID: "delete", habitID: "walk", occurredAtMillis: instant + 1, asOfMillis: instant),
        ] { await expectFailure { try await repository.deleteHabit(invalid) } }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let conflict = NativeLedgerRow(key: try NativeStorageEncoding.key("guest", "event", "delete"), ownerID: "guest",
            category: "event", identifier: "delete", payload: Data("{}".utf8))
        context.insert(conflict)
        try NativeIndexes.attach(conflict, context: context)
        try context.save()
        await expectFailure { try await repository.deleteHabit(deletion) }
        let unchanged = try await repository.habits(ownerID: "guest")
        let history = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        let createReceipt = try await repository.receipt(ownerID: "guest", operationID: "create")
        let deleteReceipt = try await repository.receipt(ownerID: "guest", operationID: "delete")
        XCTAssertEqual(unchanged, [habit()])
        XCTAssertEqual(history, [entry])
        XCTAssertNotNil(createReceipt)
        XCTAssertNil(deleteReceipt)
        try await repository.acknowledge(ownerID: "guest", eventID: "delete")
        try await repository.deleteHabit(deletion)
        try await repository.deleteOwner(ownerID: "guest")
        await expectFailure { try await repository.deleteHabit(deletion) }
    }

    func testMetadataEditsPreserveCreditAndStaleRetriesCannotUndoNewerEdits() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let edit = NativeHabitEditCommand(ownerID: "guest", operationID: "edit", habitID: "walk", title: "Evening walk",
            scheduleKind: "weekdays", scheduleParameter: nil, zoneID: "America/New_York", occurredAtMillis: instant + 1)
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            _ = try await repository.saveHabit(habit(ownerID: "other"), operationID: "create")
            let entry = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
            let updated = try await repository.editHabit(edit)
            XCTAssertEqual(updated.title, "Evening walk")
            XCTAssertEqual(updated.scheduleKind, "weekdays")
            XCTAssertEqual(updated.zoneID, "America/New_York")
            let history = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
            XCTAssertEqual(history, [entry])
            let other = try await repository.habits(ownerID: "other")
            XCTAssertEqual(other, [habit(ownerID: "other")])
            _ = try await repository.editHabit(NativeHabitEditCommand(ownerID: "guest", operationID: "edit-again", habitID: "walk",
                title: "Morning walk", scheduleKind: "daily", scheduleParameter: nil, zoneID: "Asia/Shanghai", occurredAtMillis: instant + 2))
            try await repository.acknowledge(ownerID: "guest", eventID: "edit")
            let retry = try await repository.editHabit(edit)
            XCTAssertEqual(retry.title, "Morning walk")
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let retry = try await repository.editHabit(edit)
        XCTAssertEqual(retry.title, "Morning walk")
        let targetURL = try storeURL()
        defer { try? FileManager.default.removeItem(at: targetURL.deletingLastPathComponent()) }
        let target = NativeRepository(modelContainer: try NativeStore.open(url: targetURL))
        try await target.importOwner(ownerID: "guest", contents: repository.exportOwner(ownerID: "guest"))
        let restoredRetry = try await target.editHabit(edit)
        let history = try await target.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        XCTAssertEqual(restoredRetry.title, "Morning walk")
        XCTAssertEqual(history[0].zoneID, "Asia/Shanghai")
    }

    func testInvalidMetadataEditsAndEventCollisionsLeaveStateUnchanged() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try NativeStore.open(url: url)
        let repository = NativeRepository(modelContainer: container)
        _ = try await repository.saveHabit(habit(), operationID: "create")
        let edit = NativeHabitEditCommand(ownerID: "guest", operationID: "edit", habitID: "walk", title: "Evening walk",
            scheduleKind: "daily", scheduleParameter: nil, zoneID: "Asia/Shanghai", occurredAtMillis: instant + 1)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let conflict = NativeLedgerRow(key: try NativeStorageEncoding.key("guest", "event", "edit"), ownerID: "guest",
            category: "event", identifier: "edit", payload: Data("{}".utf8))
        context.insert(conflict)
        try NativeIndexes.attach(conflict, context: context)
        try context.save()
        await expectFailure { _ = try await repository.editHabit(edit) }
        let unchanged = try await repository.habits(ownerID: "guest")
        let receipt = try await repository.receipt(ownerID: "guest", operationID: "edit")
        XCTAssertEqual(unchanged, [habit()])
        XCTAssertNil(receipt)
        try await repository.acknowledge(ownerID: "guest", eventID: "edit")
        await expectFailure {
            _ = try await repository.editHabit(NativeHabitEditCommand(ownerID: "guest", operationID: "invalid", habitID: "walk",
                title: " ", scheduleKind: "daily", scheduleParameter: nil, zoneID: "Asia/Shanghai", occurredAtMillis: self.instant + 1))
        }
        _ = try await repository.editHabit(edit)
        await expectFailure {
            _ = try await repository.editHabit(NativeHabitEditCommand(ownerID: "guest", operationID: "edit", habitID: "walk",
                title: "Different", scheduleKind: "daily", scheduleParameter: nil, zoneID: "Asia/Shanghai", occurredAtMillis: self.instant + 1))
        }
        try await repository.deleteOwner(ownerID: "guest")
        await expectFailure { _ = try await repository.editHabit(edit) }
    }

    func testArchivalPreservesHistoryAndRetryCannotUndoRestoration() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let archive = NativeHabitArchiveCommand(ownerID: "guest", operationID: "archive", habitID: "walk", archived: true, occurredAtMillis: instant + 1)
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            _ = try await repository.saveHabit(habit(ownerID: "other"), operationID: "create")
            _ = try await repository.recordProgress(command())
            _ = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
            let archived = try await repository.setHabitArchived(archive)
            XCTAssertTrue(archived.archived)
            let other = try await repository.habits(ownerID: "other")
            XCTAssertFalse(other[0].archived)
            await expectFailure { _ = try await repository.recordProgress(self.command(operationID: "blocked", recordID: "blocked")) }
            _ = try await repository.exportOwner(ownerID: "guest")
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let retried = try await repository.setHabitArchived(archive)
        XCTAssertTrue(retried.archived)
        try await repository.acknowledge(ownerID: "guest", eventID: "archive")
        _ = try await repository.setHabitArchived(NativeHabitArchiveCommand(ownerID: "guest", operationID: "restore", habitID: "walk", archived: false, occurredAtMillis: instant + 2))
        let restored = try await repository.setHabitArchived(archive)
        XCTAssertFalse(restored.archived)
        let events = try await repository.events(ownerID: "guest")
        XCTAssertFalse(events.contains { $0.eventID == "archive" })
        let target = try storeURL()
        defer { try? FileManager.default.removeItem(at: target.deletingLastPathComponent()) }
        let restoredRepository = NativeRepository(modelContainer: try NativeStore.open(url: target))
        let backup = try await repository.exportOwner(ownerID: "guest")
        try await restoredRepository.importOwner(ownerID: "guest", contents: backup)
        let restoredRetry = try await restoredRepository.setHabitArchived(archive)
        let history = try await restoredRepository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        let progress = try await restoredRepository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        XCTAssertFalse(restoredRetry.archived)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(progress.count, 1)
    }

    func testArchivalFailuresPreserveStateAndRejectInvalidCommands() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try NativeStore.open(url: url)
        let repository = NativeRepository(modelContainer: container)
        _ = try await repository.saveHabit(habit(), operationID: "create")
        _ = try await repository.recordProgress(command())
        let archive = NativeHabitArchiveCommand(ownerID: "guest", operationID: "archive", habitID: "walk", archived: true, occurredAtMillis: instant + 1)
        do {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let conflict = NativeLedgerRow(key: try NativeStorageEncoding.key("guest", "event", "archive"), ownerID: "guest",
                category: "event", identifier: "archive", payload: Data("{}".utf8))
            context.insert(conflict)
            try NativeIndexes.attach(conflict, context: context)
            try context.save()
        }
        await expectFailure { _ = try await repository.setHabitArchived(archive) }
        let unchanged = try await repository.habits(ownerID: "guest")
        let receipt = try await repository.receipt(ownerID: "guest", operationID: "archive")
        XCTAssertEqual(unchanged, [habit()])
        XCTAssertNil(receipt)
        try await repository.acknowledge(ownerID: "guest", eventID: "archive")
        for invalid in [
            NativeHabitArchiveCommand(ownerID: "missing-owner", operationID: "archive", habitID: "walk", archived: true, occurredAtMillis: instant + 1),
            NativeHabitArchiveCommand(ownerID: "guest", operationID: "archive", habitID: "walk", archived: true, occurredAtMillis: instant + 2, asOfMillis: instant + 1),
            NativeHabitArchiveCommand(ownerID: "guest", operationID: "archive", habitID: "walk", archived: true, occurredAtMillis: instant - 1),
        ] {
            await expectFailure { _ = try await repository.setHabitArchived(invalid) }
        }
        _ = try await repository.setHabitArchived(archive)
        await expectFailure {
            _ = try await repository.setHabitArchived(NativeHabitArchiveCommand(ownerID: "guest", operationID: "archive", habitID: "walk", archived: false, occurredAtMillis: self.instant + 1))
        }
        let progress = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        XCTAssertEqual(progress.count, 1)
        try await repository.deleteOwner(ownerID: "guest")
        await expectFailure { _ = try await repository.setHabitArchived(archive) }
    }

    func testProgressAndAcknowledgedRetrySurviveNewContainer() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original: NativeEntry
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            original = try await repository.recordProgress(command())
            try await repository.acknowledge(ownerID: "guest", eventID: "progress")
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let retried = try await repository.recordProgress(command(asOfMillis: instant + 86_400_000))
        XCTAssertEqual(original, retried)
        XCTAssertEqual(retried.value, 400)
        XCTAssertEqual(retried.zoneID, "Asia/Shanghai")
        let progress = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        let completions = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        let events = try await repository.events(ownerID: "guest")
        XCTAssertEqual(progress.count, 1)
        XCTAssertTrue(completions.isEmpty)
        XCTAssertEqual(events.count, 1)
        await expectFailure { _ = try await repository.recordProgress(self.command(value: 500)) }
    }

    func testBackupRoundTripAndDeletionFenceSurviveFreshContainer() async throws {
        let source = try storeURL()
        let target = try storeURL()
        defer {
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: target.deletingLastPathComponent())
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: source))
        _ = try await repository.saveHabit(habit(), operationID: "create")
        _ = try await repository.recordProgress(command())
        _ = try await repository.complete(command(operationID: "complete", recordID: "done", value: 1000))
        try await repository.acknowledge(ownerID: "guest", eventID: "progress")
        let backup = try await repository.exportOwner(ownerID: "guest")
        do {
            let restored = NativeRepository(modelContainer: try NativeStore.open(url: target))
            try await restored.importOwner(ownerID: "guest", contents: backup)
            try await restored.importOwner(ownerID: "guest", contents: backup)
            _ = try await restored.recordProgress(command())
            let events = try await restored.events(ownerID: "guest")
            let completions = try await restored.entries(ownerID: "guest", habitID: "walk", kind: .completion)
            XCTAssertEqual(events.count, 2)
            XCTAssertEqual(completions.count, 1)
            _ = try await restored.saveHabit(habit(ownerID: "other"), operationID: "create")
            try await restored.deleteOwner(ownerID: "guest")
            try await restored.deleteOwner(ownerID: "guest")
            let other = try await restored.habits(ownerID: "other")
            XCTAssertEqual(other.count, 1)
        }
        let restored = NativeRepository(modelContainer: try NativeStore.open(url: target))
        await expectFailure { try await restored.importOwner(ownerID: "guest", contents: backup) }
        await expectFailure { _ = try await restored.saveHabit(self.habit(), operationID: "create") }
        let remaining = try await restored.habits(ownerID: "guest")
        let events = try await restored.events(ownerID: "guest")
        let receipt = try await restored.receipt(ownerID: "guest", operationID: "create")
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(receipt)
    }

    func testBackupRejectsMalformedOwnershipVersionAndConflictsAtomically() async throws {
        let source = try storeURL()
        let target = try storeURL()
        defer {
            try? FileManager.default.removeItem(at: source.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: target.deletingLastPathComponent())
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: source))
        _ = try await repository.saveHabit(habit(id: "first"), operationID: "first")
        _ = try await repository.saveHabit(habit(), operationID: "create")
        let backup = try await repository.exportOwner(ownerID: "guest")
        let restored = NativeRepository(modelContainer: try NativeStore.open(url: target))
        let existing = NativeHabit(ownerID: "guest", id: "walk", title: "Existing", scheduleKind: "daily", scheduleParameter: nil,
            goalKind: "steps", target: 1000, zoneID: "Asia/Shanghai", createdAtMillis: instant, archived: false)
        _ = try await restored.saveHabit(existing, operationID: "existing")
        var unsupported = try JSONDecoder().decode(NativeBackup.self, from: backup)
        unsupported.version = 99
        await expectFailure { try await restored.importOwner(ownerID: "guest", contents: Data("{".utf8)) }
        await expectFailure { try await restored.importOwner(ownerID: "other", contents: backup) }
        let unsupportedData = try NativeStorageEncoding.encode(unsupported)
        await expectFailure { try await restored.importOwner(ownerID: "guest", contents: unsupportedData) }
        await expectFailure { try await restored.importOwner(ownerID: "guest", contents: backup) }
        let habits = try await restored.habits(ownerID: "guest")
        let events = try await restored.events(ownerID: "guest")
        XCTAssertEqual(habits, [existing])
        XCTAssertEqual(events.count, 1)
    }

    func testOutboxConflictRollsBackEntryAndReceipt() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try NativeStore.open(url: url)
        let repository = NativeRepository(modelContainer: container)
        _ = try await repository.saveHabit(habit(), operationID: "create")
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let event = NativeEvent(ownerID: "guest", eventID: "progress", kind: "test", entityID: "entry",
                                payload: Data("{}".utf8), createdAtMillis: instant)
        context.insert(NativeLedgerRow(key: try NativeStorageEncoding.key("guest", "event", "progress"),
                                      ownerID: "guest", category: "event", identifier: "progress",
                                      payload: try NativeStorageEncoding.encode(event)))
                        for row in try context.fetch(FetchDescriptor<NativeLedgerRow>()) { try NativeIndexes.attach(row, context: context) }
        try context.save()
        await expectFailure { _ = try await repository.recordProgress(self.command()) }
        let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        let receipt = try await repository.receipt(ownerID: "guest", operationID: "progress")
        let events = try await repository.events(ownerID: "guest")
        XCTAssertTrue(entries.isEmpty)
        XCTAssertNil(receipt)
        XCTAssertEqual(events.count, 2)
    }

    func testVersionOneUpgradePreservesRecordsAndBuildsIndexedScopes() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = habit()
        do {
            let schema = Schema(versionedSchema: NativeSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration("DailyGoNative", schema: schema,
                url: url, allowsSave: true, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let request = try NativeStorageEncoding.encode(original)
            let event = NativeEvent(ownerID: "guest", eventID: "create", kind: "habit.created", entityID: "walk", payload: request, createdAtMillis: instant)
            let receipt = NativeReceipt(ownerID: "guest", operationID: "create", kind: "habit.created", request: request, resultID: "walk")
            for (category, identifier, payload) in [("habit", "walk", request), ("event", "create", try NativeStorageEncoding.encode(event)),
                                                   ("receipt", "create", try NativeStorageEncoding.encode(receipt))] {
                context.insert(NativeSchemaV1.LedgerRow(key: try NativeStorageEncoding.key("guest", category, identifier),
                    ownerID: "guest", category: category, identifier: identifier, payload: payload))
            }
            try context.save()
        }
        let container = try NativeStore.open(url: url)
        let repository = NativeRepository(modelContainer: container)
        let habits = try await repository.habits(ownerID: "guest")
        let retried = try await repository.saveHabit(original, operationID: "create")
        let events = try await repository.events(ownerID: "guest")
        XCTAssertEqual(habits, [original])
        XCTAssertEqual(retried, original)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<NativeScopeRow>()), 3)
        _ = try await repository.recordProgress(command())
        let progress = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        XCTAssertEqual(progress.count, 1)
    }

    func testLegacyImportIsReadOnlyResolvedAndRetrySafe() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let source = url.deletingLastPathComponent().appendingPathComponent("legacy.sqlite")
        let fixtureURL = try XCTUnwrap(Bundle(for: NativeStorageTests.self).url(forResource: "v1", withExtension: "json"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(source.path, &connection), SQLITE_OK)
        do {
            defer { sqlite3_close(connection) }
            for sql in fixture["statements"] as! [String] { XCTAssertEqual(sqlite3_exec(connection, sql, nil, nil, nil), SQLITE_OK) }
        }
        let original = try Data(contentsOf: source)
        XCTAssertThrowsError(try NativeStore.open(url: source))
        XCTAssertEqual(try Data(contentsOf: source), original)
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let unresolved = try await repository.importLegacy(url: source, ownerID: "guest", zones: [:], acceptUnverified: false)
        XCTAssertFalse(unresolved.imported)
        let result = try await repository.importLegacy(url: source, ownerID: "guest", zones: ["walk": "Asia/Shanghai"], acceptUnverified: true)
        XCTAssertTrue(result.imported)
        XCTAssertTrue(result.issues.contains { $0.code == "UNVERIFIED_PROVENANCE" })
        let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        XCTAssertEqual(entries.first?.id, "done")
        XCTAssertEqual(entries.first?.creditedDate, "2026-10-06")
        XCTAssertEqual(entries.first?.creditReason, .legacyImported)
        try await repository.acknowledge(ownerID: "guest", eventID: "legacy-complete")
        _ = try await repository.importLegacy(url: source, ownerID: "guest", zones: ["walk": "Asia/Shanghai"], acceptUnverified: true)
        let events = try await repository.events(ownerID: "guest")
        XCTAssertEqual(events.map(\.eventID), ["legacy-create"])
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testReadOnlySaveFailureRollsBackAndWritableReopenRecovers() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
        }
        do {
            let schema = Schema(versionedSchema: NativeSchemaV2.self)
            let container = try ModelContainer(for: schema, migrationPlan: NativeMigrationPlan.self, configurations: [
                ModelConfiguration("DailyGoNative", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)])
            let repository = NativeRepository(modelContainer: container)
            for _ in 0..<2 {
                await expectFailure { _ = try await repository.recordProgress(self.command()) }
                let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
                let receipt = try await repository.receipt(ownerID: "guest", operationID: "progress")
                let habits = try await repository.habits(ownerID: "guest")
                let events = try await repository.events(ownerID: "guest")
                XCTAssertTrue(entries.isEmpty)
                XCTAssertNil(receipt)
                XCTAssertEqual(habits, [habit()])
                XCTAssertEqual(events.map(\.eventID), ["create"])
            }
        }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        _ = try await repository.recordProgress(command())
        let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        XCTAssertEqual(entries.count, 1)
    }

    func testUnsupportedNativeSchemaFailsWithoutDeletingItsData() throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let schema = Schema(versionedSchema: UnsupportedNativeSchema.self)
        let configuration = ModelConfiguration("Unsupported", schema: schema, url: url, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            context.insert(UnsupportedNativeSchema.UnknownRow(value: "preserved"))
            try context.save()
        }
        XCTAssertThrowsError(try NativeStore.open(url: url))
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let rows = try ModelContext(container).fetch(FetchDescriptor<UnsupportedNativeSchema.UnknownRow>())
        XCTAssertEqual(rows.map(\.value), ["preserved"])
    }

    func testConcurrentCompletionsCountOnceAndOwnersRemainIsolated() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        for owner in ["guest", "another-owner"] {
            _ = try await repository.saveHabit(habit(ownerID: owner), operationID: "create")
        }
        let base = command(operationID: "complete", value: 1000)
        let results = try await withThrowingTaskGroup(of: NativeEntry.self) { group in
            for number in 0..<20 {
                let request = NativeEntryCommand(ownerID: base.ownerID, operationID: "complete-\(number)", recordID: "entry-\(number)",
                    habitID: base.habitID, occurredAtMillis: base.occurredAtMillis, value: base.value,
                    workoutStartedAtMillis: nil, asOfMillis: nil)
                group.addTask { try await repository.complete(request) }
            }
            var results: [NativeEntry] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(Set(results.map(\.id)).count, 1)
        _ = try await repository.complete(command(ownerID: "another-owner", operationID: "complete", value: 1000))
        let guest = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        let other = try await repository.entries(ownerID: "another-owner", habitID: "walk", kind: .completion)
        XCTAssertEqual(guest.count, 1)
        XCTAssertEqual(other.count, 1)
        try await repository.acknowledge(ownerID: "guest", eventID: "create")
        let otherEvents = try await repository.events(ownerID: "another-owner")
        XCTAssertEqual(otherEvents.count, 2)
    }

    func testInvalidFutureArchivedAndBelowTargetCompletionWritesAreAtomic() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        _ = try await repository.saveHabit(habit(), operationID: "create")
        _ = try await repository.saveHabit(habit(id: "archived", archived: true), operationID: "archive")
        for value in [-1.0, Double.nan, Double.infinity, 0.5, 1000.0] {
            await expectFailure { _ = try await repository.recordProgress(self.command(value: value)) }
        }
        await expectFailure { _ = try await repository.recordProgress(self.command(asOfMillis: self.instant - 1)) }
        await expectFailure { _ = try await repository.recordProgress(self.command(habitID: "archived")) }
        await expectFailure { _ = try await repository.complete(self.command()) }
        let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        let events = try await repository.events(ownerID: "guest")
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(events.count, 2)
    }

    func testGraceCreditSurvivesFreshContainerAndCorruptStoreIsNotReplaced() async throws {
        let url = try storeURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ended: Int64 = 1_791_310_500_000
        let started: Int64 = 1_791_301_500_000
        let original: NativeEntry
        do {
            let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
            _ = try await repository.saveHabit(habit(), operationID: "create")
            original = try await repository.complete(NativeEntryCommand(ownerID: "guest", operationID: "complete", recordID: "entry",
                habitID: "walk", occurredAtMillis: ended, value: 1000, workoutStartedAtMillis: started, asOfMillis: nil))
        }
        XCTAssertEqual(original.creditedDate, "2026-10-06")
        XCTAssertEqual(original.creditReason, .midnightGrace)
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .completion)
        XCTAssertEqual(entries, [original])
        let corruptURL = url.deletingLastPathComponent().appendingPathComponent("corrupt.store")
        let bytes = Data(repeating: 0x42, count: 8192)
        try bytes.write(to: corruptURL)
        XCTAssertThrowsError(try NativeStore.open(url: corruptURL))
        XCTAssertEqual(try Data(contentsOf: corruptURL), bytes)
    }
}