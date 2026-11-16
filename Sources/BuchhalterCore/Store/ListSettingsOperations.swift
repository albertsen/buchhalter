import Foundation
import SwiftData

/// The sort levels (one setting for every list) and the view mode of a list
/// as the views need them.
public struct ListPreferences: Equatable, Sendable {
    public var sortLevels: SortLevels
    public var viewMode: ViewMode

    public static let `default` = ListPreferences(sortLevels: .default, viewMode: .list)
}

extension ListSettings {
    /// The `key` of the one row whose sort levels apply to every list and
    /// collection. Never a list's own key.
    public static let sortKey = "sort"
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
        default:
            return settings
                .filter { $0.collection == nil && $0.key == list.settingsKey }
                .max { $0.updatedAt < $1.updatedAt }
        }
    }

    /// The global sort row; the newest wins.
    @MainActor
    static func resolveSort(among settings: [ListSettings]) -> ListSettings? {
        settings.filter { $0.collection == nil && $0.key == sortKey }.max { $0.updatedAt < $1.updatedAt }
    }

    /// The sort levels for every list. Until the global row exists, the sort
    /// the user last chose for any one list (from before sorting was global).
    @MainActor
    public static func sortLevels(among settings: [ListSettings], collections: [Collection]) -> SortLevels {
        if let global = resolveSort(among: settings) { return SortLevels(raw: global.sortLevelsRaw) }
        let lists = settings + collections.compactMap(\.settings)
        let latest = lists.filter { $0.key != sortKey && $0.key != sidebarOrderKey && !$0.sortLevelsRaw.isEmpty }.max { $0.updatedAt < $1.updatedAt }
        return latest.map { SortLevels(raw: $0.sortLevelsRaw) } ?? .default
    }

    /// The order of the built-in lists; the newest row wins. A missing or
    /// damaged value gives the default order (`LibraryListOrder(raw:)`).
    @MainActor
    public static func libraryListOrder(among settings: [ListSettings]) -> LibraryListOrder {
        let row = settings.filter { $0.collection == nil && $0.key == sidebarOrderKey }.max { $0.updatedAt < $1.updatedAt }
        return row.map { LibraryListOrder(raw: $0.sortLevelsRaw) } ?? LibraryListOrder()
    }

    @MainActor
    public static func preferences(
        for list: LibraryListID, among settings: [ListSettings], collections: [Collection]
    ) -> ListPreferences {
        let own = resolve(for: list, among: settings, collections: collections)
        return ListPreferences(
            sortLevels: sortLevels(among: settings, collections: collections),
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

    /// Sets the sort of every list and collection.
    public func setSortLevels(_ levels: SortLevels) throws {
        try withoutUndo {
            let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
            let settings: ListSettings
            if let existing = ListSettings.resolveSort(among: all) {
                settings = existing
            } else {
                settings = ListSettings()
                settings.key = ListSettings.sortKey
                context.insert(settings)
            }
            settings.sortLevelsRaw = levels.isDefault ? "" : levels.raw
            settings.updatedAt = .now
        }
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

    public func resetSort() throws {
        try setSortLevels(.default)
    }

    public func setViewMode(_ mode: ViewMode, for list: LibraryListID) throws {
        try withoutUndo {
            let settings = settingsObject(for: list)
            settings?.viewModeRaw = mode.rawValue
            settings?.updatedAt = .now
        }
    }

    /// The existing settings object, or a new one. Nil only for a collection
    /// that no longer exists.
    private func settingsObject(for list: LibraryListID) -> ListSettings? {
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
