import Foundation
import SwiftData

@MainActor
extension Library {
    // MARK: Names

    /// Nil when the name is acceptable: not empty after trimming, and not
    /// taken (compared case- and diacritic-folded). `excluding` lets a
    /// collection keep its own name when it is renamed.
    public func validateCollectionName(_ name: String, excluding: Collection? = nil) -> LibraryError? {
        let normalized = AuthorName.normalize(name)
        if normalized.isEmpty { return .emptyCollectionName }
        let key = TextFolding.fold(normalized)
        let taken = fetchCollections().contains {
            $0 !== excluding && TextFolding.fold(AuthorName.normalize($0.name)) == key
        }
        return taken ? .duplicateCollectionName : nil
    }

    // MARK: Create, rename, delete, reorder

    @discardableResult
    public func createCollection(named name: String) throws -> Collection {
        if let error = validateCollectionName(name) { throw error }
        return try change("New Collection") { makeCollection(named: name) }
    }

    /// One undo step for "New Collection…" in the book menu.
    @discardableResult
    public func createCollection(named name: String, adding book: Book) throws -> Collection {
        if let error = validateCollectionName(name) { throw error }
        return try change("New Collection") {
            let collection = makeCollection(named: name)
            book.collections?.append(collection)
            return collection
        }
    }

    public func renameCollection(_ collection: Collection, to name: String) throws {
        if let error = validateCollectionName(name, excluding: collection) { throw error }
        try change("Rename Collection") {
            collection.name = AuthorName.normalize(name)
        }
    }

    /// Books stay. The collection's list settings go with it (cascade).
    public func deleteCollection(_ collection: Collection) throws {
        try change("Delete Collection") {
            context.delete(collection)
        }
    }

    /// `offsets` and `destination` follow `onMove`: they index the collections
    /// sorted by `sortIndex`. The result is renumbered 0…n.
    public func moveCollections(fromOffsets offsets: IndexSet, toOffset destination: Int) throws {
        try change("Move Collection") {
            let current = fetchCollections()
            var ordered = current.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
            let moving = offsets.sorted().compactMap { current.indices.contains($0) ? current[$0] : nil }
            let target = destination - offsets.filter { $0 < destination }.count
            ordered.insert(contentsOf: moving, at: max(0, min(target, ordered.count)))
            for (index, collection) in ordered.enumerated() where collection.sortIndex != Double(index) {
                collection.sortIndex = Double(index)
            }
        }
    }

    // MARK: Membership

    public func add(_ book: Book, to collection: Collection) throws {
        guard !(book.collections ?? []).contains(where: { $0 === collection }) else { return }
        try change("Add to Collection") {
            book.collections?.append(collection)
        }
    }

    public func remove(_ book: Book, from collection: Collection) throws {
        try change("Remove from Collection") {
            book.collections?.removeAll { $0 === collection }
        }
    }

    /// Adds the book, or removes it when it is already in the collection.
    public func toggle(_ book: Book, in collection: Collection) throws {
        if (book.collections ?? []).contains(where: { $0 === collection }) {
            try remove(book, from: collection)
        } else {
            try add(book, to: collection)
        }
    }

    // MARK: Helpers

    private func makeCollection(named name: String) -> Collection {
        let collection = Collection()
        collection.name = AuthorName.normalize(name)
        collection.sortIndex = (fetchCollections().map(\.sortIndex).max() ?? -1) + 1
        context.insert(collection)
        return collection
    }
}
