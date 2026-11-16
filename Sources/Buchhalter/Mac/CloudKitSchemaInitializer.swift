import CloudKit
import CoreData
import Foundation
import SwiftData
import BuchhalterCore

// Mac-only, development only. CloudKit's production schema is deployed from
// the development environment, and SwiftData cannot initialize it directly.
// `make cloudkit-schema` builds a second bundle with the Development
// environment; started with `-initializeCloudKitSchema YES` it creates the
// record types from the SwiftData model through an NSPersistentCloudKitContainer
// on a scratch store, logs the result and quits. It never opens the library.

enum CloudKitSchemaInitializer {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "initializeCloudKitSchema") }

    static func runAndExit() -> Never {
        func finish(_ line: String, code: Int32) -> Never {
            FileHandle.standardError.write(Data("cloudkit-schema: \(line)\n".utf8))
            exit(code)
        }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: LibraryContainer.schema) else {
            finish("could not build the Core Data model from the SwiftData schema", code: 1)
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: "schema-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            finish("\(error)", code: 1)
        }
        defer { try? FileManager.default.removeItem(at: folder) }

        let container = NSPersistentCloudKitContainer(name: "Buchhalter", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: folder.appending(path: "schema.store"))
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: SyncConfiguration.containerID)
        // Synchronously, so the schema call below runs on a loaded store.
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { finish("could not load the scratch store: \(loadError)", code: 1) }

        do {
            try container.initializeCloudKitSchema(options: [])
            finish("ok (\(SyncConfiguration.containerID))", code: 0)
        } catch {
            finish("\(error)", code: 1)
        }
    }
}
