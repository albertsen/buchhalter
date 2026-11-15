import Foundation
import SwiftData

/// Every schema in order. Add a stage here with each new `VersionedSchema`.
public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
