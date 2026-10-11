import Foundation
import SwiftData
import SQLite3

enum NativeSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [LedgerRow.self] }

    @Model
    final class LedgerRow {
        @Attribute(.unique) var key: String
        var ownerID: String
        var category: String
        var identifier: String
        var payload: Data

        init(key: String, ownerID: String, category: String, identifier: String, payload: Data) {
            self.key = key
            self.ownerID = ownerID
            self.category = category
            self.identifier = identifier
            self.payload = payload
        }
    }
}

enum NativeSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [LedgerRow.self, ScopeRow.self] }

    @Model
    final class LedgerRow {
        @Attribute(.unique) var key: String
        var ownerID: String
        var category: String
        var identifier: String
        var payload: Data
        var ownerScope: ScopeRow?
        var habitScope: ScopeRow?

        init(key: String, ownerID: String, category: String, identifier: String, payload: Data) {
            self.key = key
            self.ownerID = ownerID
            self.category = category
            self.identifier = identifier
            self.payload = payload
        }
    }

    @Model
    final class ScopeRow {
        @Attribute(.unique) var key: String
        var ownerID: String
        @Relationship(deleteRule: .nullify, inverse: \LedgerRow.ownerScope) var records: [LedgerRow] = []
        @Relationship(deleteRule: .nullify, inverse: \LedgerRow.habitScope) var entries: [LedgerRow] = []

        init(key: String, ownerID: String) {
            self.key = key
            self.ownerID = ownerID
        }
    }
}

typealias NativeLedgerRow = NativeSchemaV2.LedgerRow
typealias NativeScopeRow = NativeSchemaV2.ScopeRow

enum NativeIndexes {
    static func scope(context: ModelContext, ownerID: String, category: String, habitID: String = "") throws -> NativeScopeRow {
        let key = try NativeStorageEncoding.key(ownerID, category, habitID)
        var descriptor = FetchDescriptor<NativeScopeRow>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        if let existing = try context.fetch(descriptor).first { return existing }
        let scope = NativeScopeRow(key: key, ownerID: ownerID)
        context.insert(scope)
        return scope
    }

    static func attach(_ row: NativeLedgerRow, context: ModelContext) throws {
        row.ownerScope = try scope(context: context, ownerID: row.ownerID, category: row.category)
        if row.category == "completion" || row.category == "progress" {
            let entry = try NativeStorageEncoding.decode(NativeEntry.self, from: row.payload)
            row.habitScope = try scope(context: context, ownerID: row.ownerID, category: row.category, habitID: entry.habitID)
        }
    }
}

enum NativeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NativeSchemaV1.self, NativeSchemaV2.self] }
    static var stages: [MigrationStage] {
        [.custom(fromVersion: NativeSchemaV1.self, toVersion: NativeSchemaV2.self, willMigrate: nil, didMigrate: { context in
            for row in try context.fetch(FetchDescriptor<NativeLedgerRow>()) { try NativeIndexes.attach(row, context: context) }
            try context.save()
        })]
    }
}

enum NativeStore {
    static func open(url: URL) throws -> ModelContainer {
        guard url.isFileURL else { throw NativeStorageError.invalidDefinition }
        if FileManager.default.fileExists(atPath: url.path) {
            var connection: OpaquePointer?
            guard sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let connection else {
                if let connection { sqlite3_close(connection) }
                throw NativeStorageError.invalidStore
            }
            defer { sqlite3_close(connection) }
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(connection, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'Z_METADATA'", -1, &statement, nil) == SQLITE_OK else {
                if let statement { sqlite3_finalize(statement) }
                throw NativeStorageError.invalidStore
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw NativeStorageError.invalidStore }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: NativeSchemaV2.self)
        let configuration = ModelConfiguration("DailyGoNative", schema: schema, url: url,
                                               allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: NativeMigrationPlan.self, configurations: [configuration])
    }
}