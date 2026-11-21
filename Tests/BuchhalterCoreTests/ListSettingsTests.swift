import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

@MainActor
struct ListSettingsTests {
    @Test func defaultWhenMissing() throws {
        let t = try TestLibrary()
        #expect(t.library.preferences(for: .reading) == .default)
        #expect(t.library.preferences(for: .collection(UUID())) == .default)
    }

    @Test func eachListHasItsOwnSort() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        let title = SortLevels(levels: [SortLevel(field: .title)])
        let pages = SortLevels(levels: [SortLevel(field: .pages, direction: .descending)])
        try t.library.setSortLevels(title, for: .reading)
        try t.library.setSortLevels(pages, for: .collection(collection.id))
        try t.library.setViewMode(.grid, for: .collection(collection.id))
        #expect(t.library.preferences(for: .reading) == ListPreferences(sortLevels: title, viewMode: .list))
        #expect(t.library.preferences(for: .all) == .default)
        #expect(t.library.preferences(for: .collection(collection.id)) == ListPreferences(sortLevels: pages, viewMode: .grid))
        #expect(t.library.preferences(for: .collection(UUID())) == .default)
    }

    @Test func aViewModeChangeKeepsTheSort() throws {
        let t = try TestLibrary()
        let year = SortLevels(levels: [SortLevel(field: .year, direction: .descending)])
        try t.library.setSortLevels(year, for: .read)
        try t.library.setViewMode(.grid, for: .read)
        #expect(t.library.preferences(for: .read) == ListPreferences(sortLevels: year, viewMode: .grid))
    }

    /// The state the global sort left: each list's sort from before it, and the
    /// global row with the sort the user sees everywhere.
    private func insertGlobalSortState(_ t: TestLibrary, collection: Collection) {
        for (key, raw) in [("reading", "title:asc"), ("read", "pages:desc"), ("wantToRead", "")] {
            let old = ListSettings()
            old.key = key
            old.sortLevelsRaw = raw
            old.viewModeRaw = key == "read" ? "grid" : "list"
            old.updatedAt = date(2026, 11, 1)
            t.context.insert(old)
        }
        let own = ListSettings()
        own.sortLevelsRaw = "added:desc"
        own.collection = collection
        t.context.insert(own)
        let global = ListSettings()
        global.key = ListSettings.globalSortKey
        global.sortLevelsRaw = "year:asc"
        global.updatedAt = date(2026, 11, 16)
        t.context.insert(global)
    }

    @Test func theGlobalSortShowsInEveryListUntilAdopted() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        insertGlobalSortState(t, collection: collection)
        for list in LibraryListID.builtIn + [.collection(collection.id)] {
            #expect(t.library.preferences(for: list).sortLevels.raw == "year:asc")
        }
    }

    @Test func adoptingGivesEveryListTheGlobalSortAndDropsTheRow() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        insertGlobalSortState(t, collection: collection)
        #expect(try t.library.adoptGlobalSort())
        let rows = try t.context.fetch(FetchDescriptor<ListSettings>())
        #expect(!rows.contains { $0.key == ListSettings.globalSortKey })
        for list in LibraryListID.builtIn + [.collection(collection.id)] {
            #expect(t.library.preferences(for: list).sortLevels.raw == "year:asc")
        }
        #expect(t.library.preferences(for: .read).viewMode == .grid)
        #expect(try !t.library.adoptGlobalSort())
    }

    @Test func sortingOneListAdoptsTheGlobalSortFirst() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        insertGlobalSortState(t, collection: collection)
        try t.library.setSortLevels(SortLevels(levels: [SortLevel(field: .rating)]), for: .reading)
        #expect(t.library.preferences(for: .reading).sortLevels.raw == "rating:asc")
        #expect(t.library.preferences(for: .read).sortLevels.raw == "year:asc")
        #expect(t.library.preferences(for: .collection(collection.id)).sortLevels.raw == "year:asc")
    }

    @Test func adoptingWithoutAGlobalRowChangesNothing() throws {
        let t = try TestLibrary()
        let title = SortLevels(levels: [SortLevel(field: .title)])
        try t.library.setSortLevels(title, for: .all)
        #expect(try !t.library.adoptGlobalSort())
        #expect(t.library.preferences(for: .all).sortLevels == title)
        #expect(try t.context.fetchCount(FetchDescriptor<ListSettings>()) == 1)
    }

    @Test func newestDuplicateWins() throws {
        let t = try TestLibrary()
        let old = ListSettings()
        old.key = "reading"
        old.viewModeRaw = "grid"
        old.updatedAt = date(2020, 1, 1)
        let new = ListSettings()
        new.key = "reading"
        new.viewModeRaw = "list"
        new.updatedAt = date(2026, 1, 1)
        t.context.insert(old)
        t.context.insert(new)
        #expect(t.library.preferences(for: .reading).viewMode == .list)
    }

    @Test func resetRestoresTheDefault() throws {
        let t = try TestLibrary()
        try t.library.setSortLevels(SortLevels(levels: [SortLevel(field: .pages)]), for: .read)
        try t.library.resetSort(for: .read)
        #expect(t.library.preferences(for: .read).sortLevels == .default)
        #expect(try t.context.fetchCount(FetchDescriptor<ListSettings>()) == 1)
    }

    @Test func unknownViewModeFallsBackToList() {
        #expect(ViewMode(raw: "cinema") == .list)
        #expect(ReadingStatus(raw: "future") == .wantToRead)
    }
}

@MainActor
struct SidebarOrderTests {
    @Test func theRowRoundTripsAndIsKeptOnce() throws {
        let t = try TestLibrary()
        #expect(t.library.libraryListOrder() == LibraryListOrder())
        #expect(!t.library.hasLibraryListOrder)
        let order = LibraryListOrder(raw: "read,reading,wantToRead,all")
        try t.library.setLibraryListOrder(order)
        try t.library.setLibraryListOrder(order)
        #expect(t.library.libraryListOrder().raw == "read,reading,wantToRead,all")
        #expect(t.library.hasLibraryListOrder)
        let rows = try t.context.fetch(FetchDescriptor<ListSettings>())
        #expect(rows.filter { $0.key == ListSettings.sidebarOrderKey }.count == 1)
    }

    @Test func theNewestRowWins() throws {
        let t = try TestLibrary()
        for (year, raw) in [(2026, "all,read,reading,wantToRead"), (2025, "read,all,reading,wantToRead")] {
            let row = ListSettings()
            row.key = ListSettings.sidebarOrderKey
            row.sortLevelsRaw = raw
            row.updatedAt = date(year, 1, 1)
            t.context.insert(row)
        }
        #expect(t.library.libraryListOrder().raw == "all,read,reading,wantToRead")
    }

    @Test func aDamagedValueFallsBackLikeTheParserDoes() throws {
        let t = try TestLibrary()
        let row = ListSettings()
        row.key = ListSettings.sidebarOrderKey
        row.sortLevelsRaw = "bogus,read,read"
        t.context.insert(row)
        #expect(t.library.libraryListOrder().raw == "read,reading,wantToRead,all")
    }

    @Test func theRowIsNotMistakenForAnOldPerListSort() throws {
        let t = try TestLibrary()
        try t.library.setLibraryListOrder(LibraryListOrder(raw: "read,reading,wantToRead,all"))
        #expect(t.library.preferences(for: .reading).sortLevels == .default)
    }
}
