import Foundation
import SwiftData

/// Builds the `ModelContainer` from the current schema and the migration plan.
/// It never deletes, moves or overwrites an existing store: when the store
/// cannot be opened, the error goes to the caller.
public enum LibraryContainer {
    public static var schema: Schema { Schema(versionedSchema: SchemaV1.self) }

    public static func make(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(
            for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration]
        )
    }

    @MainActor
    public static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration]
        )
    }
}
