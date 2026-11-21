import Foundation
import SwiftData

/// The operations that change the library. Views call these instead of
/// setting model properties, so the rules (a finished reading has a date,
/// collection names are unique, one undo step per user action) hold in one
/// place and are covered by tests without a display.
@MainActor
public struct Library {
    public let context: ModelContext
    /// The window's undo manager. The context's own `undoManager` stays nil on
    /// purpose: SwiftData's undo reverts values in memory without marking the
    /// context dirty on macOS 27.2, so an undone change is never saved and the
    /// next fetch brings the old value back. `Library` records and restores
    /// changes itself instead.
    public let undoManager: UndoManager?

    public init(context: ModelContext, undoManager: UndoManager? = nil) {
        self.context = context
        self.undoManager = undoManager
    }

    // MARK: Undo grouping and saving

    /// Runs one user action as one undo step. It captures a snapshot of the
    /// library, runs the mutation, saves, captures a second snapshot, and
    /// registers undo and redo closures that write the difference back and
    /// save. No change is left to SwiftData's own undo registration.
    ///
    /// - Parameter covers: existing books whose cover the action may change or
    ///   delete. Cover bytes are read only for these and for books the action
    ///   adds, so ordinary actions never load every cover.
    ///
    /// Operations validate before they mutate. If the mutation or the save
    /// fails, the unsaved changes are rolled back and nothing is registered.
    @discardableResult
    func change<T>(
        _ name: LocalizedStringResource, covers: [Book] = [], _ body: () throws -> T
    ) throws -> T {
        let coverIDs = Set(covers.map(\.id))
        let before = LibrarySnapshot.capture(context, coverIDs: coverIDs)
        let result: T
        do {
            result = try body()
            try save()
        } catch {
            context.rollback()
            throw error
        }
        guard undoManager != nil else { return result }
        let after = LibrarySnapshot.capture(context, coverIDs: coverIDs, newBooksNotIn: Set(before.books.keys))
        let undo = LibraryDiff(from: after, to: before)
        let redo = LibraryDiff(from: before, to: after)
        if !undo.isEmpty || !redo.isEmpty {
            register(name, undo: undo, redo: redo)
        }
        return result
    }

    /// Registers one undo step. When it runs, it registers the inverse step,
    /// which the undo manager files as redo (or as undo again after a redo).
    private func register(_ name: LocalizedStringResource, undo: LibraryDiff, redo: LibraryDiff) {
        guard let manager = undoManager else { return }
        manager.beginUndoGrouping()
        // The closure holds the manager weakly: the manager owns the closure.
        manager.registerUndo(withTarget: context) { [weak manager] context in
            MainActor.assumeIsolated {
                let library = Library(context: context, undoManager: manager)
                library.apply(undo)
                do {
                    try library.save()
                } catch {
                    library.context.rollback()
                    FileHandle.standardError.write(Data("undo: \(error)\n".utf8))
                }
                library.register(name, undo: redo, redo: undo)
            }
        }
        manager.setActionName(String(localized: name))
        manager.endUndoGrouping()
    }

    /// For sort and view changes: saved at once, never on the undo stack.
    func withoutUndo<T>(_ body: () throws -> T) throws -> T {
        let result = try body()
        try save()
        return result
    }

    func save() throws {
        do {
            try context.save()
        } catch {
            throw LibraryError.saveFailed(error)
        }
    }

    // MARK: Fetching

    func fetchBooks() -> [Book] {
        (try? context.fetch(FetchDescriptor<Book>())) ?? []
    }

    func fetchCollections() -> [Collection] {
        (try? context.fetch(FetchDescriptor<Collection>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
    }

    public func book(withID id: UUID) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func collection(withID id: UUID) -> Collection? {
        var descriptor = FetchDescriptor<Collection>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    public func author(withID id: UUID) -> Author? {
        var descriptor = FetchDescriptor<Author>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}

/// Dates are stored as given. The UI passes the start of the chosen day.
func trimmedOrNil(_ text: String?) -> String? {
    guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
    return trimmed
}
