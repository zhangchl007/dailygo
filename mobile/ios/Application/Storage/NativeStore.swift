import Foundation
import SwiftData

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

typealias NativeLedgerRow = NativeSchemaV1.LedgerRow

enum NativeStore {
    static func open(url: URL) throws -> ModelContainer {
        guard url.isFileURL else { throw NativeStorageError.invalidDefinition }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: NativeSchemaV1.self)
        let configuration = ModelConfiguration("DailyGoNative", schema: schema, url: url,
                                               allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}