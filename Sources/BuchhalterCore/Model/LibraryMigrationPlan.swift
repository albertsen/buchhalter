import Foundation
import SwiftData

/// Every schema in order. Add a stage here with each new `VersionedSchema`.
public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self, SchemaV3.self] }
    public static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }

    /// Adds `Reading.stars` and copies each whole-star rating into it, so
    /// a 4 becomes 4.0. The old `rating` keeps its value.
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            let readings = try context.fetch(FetchDescriptor<SchemaV2.Reading>())
            for reading in readings where reading.stars == nil {
                if let rating = reading.rating, (1...5).contains(rating) { reading.stars = Double(rating) }
            }
            try context.save()
        }
    )

    /// Adds `Book.synopsis` and `Book.synopsisSourceRaw`, both optional.
    static let v2ToV3 = MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)
}
