import Foundation
import SwiftData

/// Builds the `ModelContainer` from the current schema and the migration plan.
/// It never deletes, moves or overwrites an existing store: when the store
/// cannot be opened, the error goes to the caller.
public enum LibraryContainer {
    public static var schema: Schema { Schema(versionedSchema: SchemaV2.self) }

    /// - Parameter cloudKitContainer: the iCloud container id that mirrors the
    ///   store into the user's private database, or nil for a store that stays
    ///   local. It is always explicit: SwiftData's default (`.automatic`) turns
    ///   sync on by itself in an app that has the CloudKit entitlement, which a
    ///   scratch store, the command line tool and the tests must never do.
    public static func make(at url: URL, cloudKitContainer: String? = nil) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema, url: url,
            cloudKitDatabase: cloudKitContainer.map { .private($0) } ?? .none
        )
        return try ModelContainer(
            for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration]
        )
    }

    @MainActor
    public static func inMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: [configuration]
        )
    }
}
