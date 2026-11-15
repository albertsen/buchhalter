import Foundation
import SwiftData

/// The sort levels and view mode of a list as the views need them.
public struct ListPreferences: Equatable, Sendable {
    public var sortLevels: SortLevels
    public var viewMode: ViewMode

    public static let `default` = ListPreferences(sortLevels: .default, viewMode: .list)
}

extension ListSettings {
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

    @MainActor
    public static func preferences(
        for list: LibraryListID, among settings: [ListSettings], collections: [Collection]
    ) -> ListPreferences {
        guard let found = resolve(for: list, among: settings, collections: collections) else { return .default }
        return ListPreferences(
            sortLevels: SortLevels(raw: found.sortLevelsRaw), viewMode: ViewMode(raw: found.viewModeRaw)
        )
    }
}

@MainActor
extension Library {
    public func preferences(for list: LibraryListID) -> ListPreferences {
        let all = (try? context.fetch(FetchDescriptor<ListSettings>())) ?? []
        return ListSettings.preferences(for: list, among: all, collections: fetchCollections())
    }

    public func setSortLevels(_ levels: SortLevels, for list: LibraryListID) throws {
        try withoutUndo {
            let settings = settingsObject(for: list)
            settings?.sortLevelsRaw = levels.isDefault ? "" : levels.raw
            settings?.updatedAt = .now
        }
    }

    public func resetSort(for list: LibraryListID) throws {
        try setSortLevels(.default, for: list)
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
