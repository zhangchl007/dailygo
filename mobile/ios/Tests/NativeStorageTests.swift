import Foundation
import SwiftData
import XCTest
@testable import DailyGo

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
        try context.save()
        await expectFailure { _ = try await repository.recordProgress(self.command()) }
        let entries = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
        let receipt = try await repository.receipt(ownerID: "guest", operationID: "progress")
        let events = try await repository.events(ownerID: "guest")
        XCTAssertTrue(entries.isEmpty)
        XCTAssertNil(receipt)
        XCTAssertEqual(events.count, 2)
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