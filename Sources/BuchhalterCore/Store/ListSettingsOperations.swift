import Foundation
import SwiftData

/// The sort levels and the view mode of a list as the views need them.
public struct ListPreferences: Equatable, Sendable {
    public var sortLevels: SortLevels
    public var viewMode: ViewMode

    public static let `default` = ListPreferences(sortLevels: .default, viewMode: .list)
}

extension ListSettings {
    /// The `key` of the row that held one sort for every list, from 2026-11-15
    /// until sorting was per list again. `Library.adoptGlobalSort` turns it
    /// into each list's own sort and deletes it; an older app on another device
    /// can still write it. Never a list's own key.
    public static let globalSortKey = "sort"
    /// The `key` of the row that holds the order of the built-in lists in the
    /// sidebar, as `LibraryListOrder.raw` in `sortLevelsRaw`. It is a view
    /// preference that syncs, so it lives in the store: a new schema version
    /// for one string would migrate the real library and add a CloudKit field
    /// for it. The attribute's name no longer fits; the key says what it holds.
    public static let sidebarOrderKey = "sidebarOrder"

    /// Duplicates can exist (no unique constraint with CloudKit); the newest wins.
    @MainActor
    public static func resolve(
        for list: LibraryListID, among settings: [ListSettings], collections: [Collection]
    ) -> ListSettings? {
        switch list {
        case .collection(let id):
            if let own = collections.first(where: { $0.id == id })?.settings { return own }
            return nil
        case .authors:
            // Authors has a fixed order and no view mode.
            return nil
        case .reading, .wantToRead, .read, .all:
            return settings
                .filter { $0.collection == nil && $0.key == list.settingsKey }
                .max { $0.updatedAt < $1.updatedAt }
        }
    }

    /// The old global sort row; the newest wins.
    @MainActor
    static func resolveGlobalSort(among settings: [ListSettings]) -> ListSettings? {
        settings.filter { $0.collection == nil && $0.key == globalSortKey }.max { $0.updatedAt < $1.updatedAt }
    }

    /// The order of the built-in lists; the newest row wins. A missing or
    /// damaged value gives the default order (`LibraryListOrder(raw:)`).
    @MainActor
    public static func libraryListOrder(among settings: [ListSettings]) -> LibraryListOrder {
        let row = settings.filter { $0.collection == nil && $0.key == sidebarOrderKey }.max { $0.updatedAt < $1.updatedAt }
        return row.map { LibraryListOrder(raw: $0.sortLevelsRaw) } ?? LibraryListOrder()
    }

    /// The list's own sort, or the old global one while it waits to be
    /// adopted, so a list shows what `adoptGlobalSort` will give it.
    @MainActor
    public static func preferences(
        for list: LibraryListID, among settings: [ListSettings], collections: [Collection]
    ) -> ListPreferences {
        let own = resolve(for: list, among: settings, collections: collections)
        let sortRaw = resolveGlobalSort(among: settings)?.sortLevelsRaw ?? own?.sortLevelsRaw ?? ""
        return ListPreferences(
            sortLevels: SortLevels(raw: sortRaw),
            viewMode: own.map { ViewMode(raw: $0.viewModeRaw) } ?? .list
        )
    }
}

@MainActor
extension Library {
    public func preferences(for list: LibraryListID) -> ListPreferences {
        let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
        return ListSettings.preferences(for: list, among: all, collections: fetchCollections())
    }

    /// Sets the sort of one list. Other lists keep theirs.
    public func setSortLevels(_ levels: SortLevels, for list: LibraryListID) throws {
        try adoptGlobalSort()
        try withoutUndo {
            let settings = settingsObject(for: list)
            settings?.sortLevelsRaw = levels.isDefault ? "" : levels.raw
            settings?.updatedAt = .now
        }
    }

    public func resetSort(for list: LibraryListID) throws {
        try setSortLevels(.default, for: list)
    }

    /// Sorting was one setting for every list and is per list again. The old
    /// global sort becomes the sort of every list and collection, so no list
    /// changes, and a list's own sort from before the global one does not come
    /// back. Then the global row goes. Runs at launch and after each iCloud
    /// import, because an older app on another device can write the row again.
    /// Returns whether a global row was there.
    @discardableResult
    public func adoptGlobalSort() throws -> Bool {
        let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
        guard let global = ListSettings.resolveGlobalSort(among: all) else { return false }
        let raw = global.sortLevelsRaw
        try withoutUndo {
            let lists = LibraryListID.builtIn + fetchCollections().map { .collection($0.id) }
            for list in lists {
                guard let settings = settingsObject(for: list) else { continue }
                settings.sortLevelsRaw = raw
                settings.updatedAt = .now
            }
            for row in all where row.collection == nil && row.key == ListSettings.globalSortKey {
                context.delete(row)
            }
        }
        return true
    }

    /// Sets the order of the built-in lists in the sidebar. Saved at once, never
    /// on the undo stack, like the sort.
    public func setLibraryListOrder(_ order: LibraryListOrder) throws {
        try withoutUndo {
            let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
            let row = all.filter { $0.collection == nil && $0.key == ListSettings.sidebarOrderKey }
                .max { $0.updatedAt < $1.updatedAt }
            let settings: ListSettings
            if let row {
                settings = row
            } else {
                settings = ListSettings()
                settings.key = ListSettings.sidebarOrderKey
                context.insert(settings)
            }
            settings.sortLevelsRaw = order.raw
            settings.updatedAt = .now
        }
    }

    public func libraryListOrder() -> LibraryListOrder {
        ListSettings.libraryListOrder(among: (try? context.fetch(FetchDescriptor<ListSettings>())) ?? [])
    }

    /// Whether the store already holds a sidebar order, so the one written
    /// from the old app's preferences is made only once.
    public var hasLibraryListOrder: Bool {
        let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
        return all.contains { $0.collection == nil && $0.key == ListSettings.sidebarOrderKey }
    }

    public func setViewMode(_ mode: ViewMode, for list: LibraryListID) throws {
        try withoutUndo {
            let settings = settingsObject(for: list)
            settings?.viewModeRaw = mode.rawValue
            settings?.updatedAt = .now
        }
    }

    /// The existing settings object, or a new one. Nil for a collection that
    /// no longer exists, and for Authors, which has no settings.
    private func settingsObject(for list: LibraryListID) -> ListSettings? {
        if list == .authors { return nil }
        let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
        let collections = fetchCollections()
        if let existing = ListSettings.resolve(for: list, among: all, collections: collections) { return existing }
        let settings = ListSettings()
        settings.key = list.settingsKey
        context.insert(settings)
        if case .collection(let id) = list {
            guard let collection = collections.first(where: { $0.id == id }) else {
                context.delete(settings)
                return nil
            }
            settings.collection = collection
        }
        return settings
    }
}
