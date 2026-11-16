import Foundation
import SwiftData

@MainActor
extension Library {
    /// Merges what two devices created independently, which no unique
    /// constraint can prevent with CloudKit. Nobody is asked and nothing goes
    /// on the undo stack. The rules pick the same survivor on every device, so
    /// two devices that merge at once converge instead of fighting.
    ///
    /// - Authors with one `AuthorName.matchKey`: the smallest `id.uuidString`
    ///   survives and takes over the others' authorships. A sort name the user
    ///   corrected (one that differs from the guess for its name) is kept.
    /// - Collections with one folded name: the earliest `createdAt`, then the
    ///   smallest id, survives with the union of the books and its own note
    ///   and place. A note it lacks comes from the next one that has one.
    /// - `ListSettings` rows with one key: the newest survives.
    ///
    /// Books are never merged: two books with one ISBN stay two (the user
    /// deletes one). Returns how many objects were removed.
    @discardableResult
    public func mergeSyncDuplicates() throws -> Int {
        try withoutUndo { mergeAuthors() + mergeCollections() + mergeSettings() }
    }

    // MARK: Authors

    private func mergeAuthors() -> Int {
        let all = (try? context.fetch(FetchDescriptor<Author>())) ?? []
        let groups = Dictionary(grouping: all.filter { !AuthorName.normalize($0.name).isEmpty }) { AuthorName.matchKey($0.name) }
        var removed = 0
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { $0.id.uuidString < $1.id.uuidString }
            let survivor = ordered[0]
            let corrected = ordered.first { !$0.sortName.isEmpty && $0.sortName != AuthorName.guessSortName($0.name) }
            if let corrected, corrected !== survivor { survivor.sortName = corrected.sortName }
            for loser in ordered.dropFirst() {
                for authorship in loser.authorships ?? [] { authorship.author = survivor }
                context.delete(loser)
                removed += 1
            }
            // A book that listed both names now lists the author twice: keep the first place.
            var seenBooks = Set<UUID>()
            for authorship in (survivor.authorships ?? []).sorted(by: { $0.position < $1.position }) {
                guard let book = authorship.book else { continue }
                if !seenBooks.insert(book.id).inserted { context.delete(authorship) }
            }
        }
        return removed
    }

    // MARK: Collections

    private func mergeCollections() -> Int {
        let all = (try? context.fetch(FetchDescriptor<Collection>())) ?? []
        let groups = Dictionary(grouping: all.filter { !AuthorName.normalize($0.name).isEmpty }) {
            TextFolding.fold(AuthorName.normalize($0.name))
        }
        var removed = 0
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted {
                $0.createdAt != $1.createdAt ? $0.createdAt < $1.createdAt : $0.id.uuidString < $1.id.uuidString
            }
            let survivor = ordered[0]
            for loser in ordered.dropFirst() {
                for book in loser.books ?? [] where !(survivor.books ?? []).contains(where: { $0 === book }) {
                    survivor.books?.append(book)
                }
                if (survivor.note ?? "").isEmpty, let note = loser.note, !note.isEmpty { survivor.note = note }
                context.delete(loser)
                removed += 1
            }
        }
        return removed
    }

    // MARK: List settings

    private func mergeSettings() -> Int {
        let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
        let groups = Dictionary(grouping: all.filter { $0.collection == nil && !$0.key.isEmpty }, by: \.key)
        var removed = 0
        for group in groups.values where group.count > 1 {
            // The newest wins; equal dates fall back to the values, so the pick does not depend on fetch order.
            let ordered = group.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return ($0.sortLevelsRaw, $0.viewModeRaw) < ($1.sortLevelsRaw, $1.viewModeRaw)
            }
            for loser in ordered.dropFirst() {
                context.delete(loser)
                removed += 1
            }
        }
        return removed
    }
}
