import Foundation
import SQLite3
import SwiftData

enum DurabilityFailure: Error { case assertion(String) }

@main
struct NativeStorageDurability {
    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw DurabilityFailure.assertion(message) }
    }

    static func full(_ error: NSError) -> Bool {
        if (error.domain == NSPOSIXErrorDomain && error.code == 28) ||
            (error.domain == NSCocoaErrorDomain && error.code == 640) ||
            error.userInfo["NSSQLiteErrorDomain"] as? Int == 13 { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, full(underlying) { return true }
        return error.localizedDescription.localizedCaseInsensitiveContains("full") ||
            error.localizedDescription.localizedCaseInsensitiveContains("space")
    }

    static func main() async throws {
        let volume = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixtureURL = URL(fileURLWithPath: CommandLine.arguments[2])
        let scratch = volume.deletingLastPathComponent()
        let legacyURL = scratch.appendingPathComponent("legacy.sqlite")
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as! [String: Any]
        var connection: OpaquePointer?
        try require(sqlite3_open(legacyURL.path, &connection) == SQLITE_OK, "Fixture open failed")
        do {
            defer { sqlite3_close(connection) }
            for sql in fixture["statements"] as! [String] {
                try require(sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK, "Fixture statement failed")
            }
        }
        let sourceBytes = try Data(contentsOf: legacyURL)
        let unresolved = try NativeLegacy.read(url: legacyURL, ownerID: "guest", zones: [:], acceptUnverified: false)
        try require(unresolved.0 == nil && !unresolved.1.isEmpty, "Ambiguous legacy source accepted")
        let converted = try NativeLegacy.read(url: legacyURL, ownerID: "guest", zones: ["walk": "Asia/Shanghai"], acceptUnverified: true)
        let archive = try NativeStorageEncoding.encode(converted.0!)
        try require(try Data(contentsOf: legacyURL) == sourceBytes, "Legacy source altered")
        let url = volume.appendingPathComponent("durability.store")
        let repository = NativeRepository(modelContainer: try NativeStore.open(url: url))
        try await repository.importOwner(ownerID: "guest", contents: archive)
        try await repository.acknowledge(ownerID: "guest", eventID: "legacy-complete")
        try await repository.importOwner(ownerID: "guest", contents: archive)
        let initialEvents = try await repository.events(ownerID: "guest")
        try require(initialEvents.count == 1, "Legacy event resurrected")
        let backup = try await repository.exportOwner(ownerID: "guest")
        let instant: Int64 = 1_791_282_600_000
        let block = Data(repeating: 0x42, count: 1024 * 1024)
        var filler = 0
        var exhausted = false
        for number in 0..<256 {
            do { try block.write(to: volume.appendingPathComponent("filler-\(number)")); filler += 1 }
            catch {
                guard full(error as NSError) else { throw error }
                exhausted = true
                break
            }
        }
        try require(exhausted && filler > 0, "Test volume did not fill")
        var failed: NativeEntryCommand?
        for number in 0..<1024 {
            let command = NativeEntryCommand(ownerID: "guest", operationID: "progress-\(number)", recordID: "entry-\(number)", habitID: "walk",
                occurredAtMillis: instant, value: 400, workoutStartedAtMillis: nil, asOfMillis: nil)
            let before = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
            let eventsBefore = try await repository.events(ownerID: "guest")
            do { _ = try await repository.recordProgress(command) }
            catch {
                guard full(error as NSError) else { throw error }
                let after = try await repository.entries(ownerID: "guest", habitID: "walk", kind: .progress)
                let eventsAfter = try await repository.events(ownerID: "guest")
                let receipt = try await repository.receipt(ownerID: "guest", operationID: command.operationID)
                try require(before == after && eventsBefore == eventsAfter && receipt == nil, "Disk-full left partial state")
                failed = command
                break
            }
        }
        try require(failed != nil, "SwiftData save did not encounter disk-full")
        for file in try FileManager.default.contentsOfDirectory(at: volume, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix("filler-") {
            try FileManager.default.removeItem(at: file)
        }
        let saved = try await repository.recordProgress(failed!)
        try await repository.acknowledge(ownerID: "guest", eventID: failed!.operationID)
        let reopened = NativeRepository(modelContainer: try NativeStore.open(url: url))
        let retried = try await reopened.recordProgress(failed!)
        try require(saved == retried, "Retry changed committed state")
        let restoreURL = scratch.appendingPathComponent("restored.store")
        let restored = NativeRepository(modelContainer: try NativeStore.open(url: restoreURL))
        try await restored.importOwner(ownerID: "guest", contents: backup)
        let restoredBackup = try await restored.exportOwner(ownerID: "guest")
        try require(restoredBackup == backup, "Backup restore changed state")
        try await restored.deleteOwner(ownerID: "guest")
        do {
            try await restored.importOwner(ownerID: "guest", contents: backup)
            throw DurabilityFailure.assertion("Deleted owner resurrected")
        } catch NativeStorageError.deletedOwner {}
        print("SwiftData real disk-full rollback/recovery, backup restore and read-only legacy import passed")
    }
}