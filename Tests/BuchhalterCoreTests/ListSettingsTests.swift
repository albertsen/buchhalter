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

    @Test func sortIsGlobalViewModeIsPerList() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        let title = SortLevels(levels: [SortLevel(field: .title)])
        try t.library.setSortLevels(title)
        try t.library.setViewMode(.grid, for: .collection(collection.id))
        #expect(t.library.preferences(for: .reading) == ListPreferences(sortLevels: title, viewMode: .list))
        #expect(t.library.preferences(for: .all).sortLevels == title)
        #expect(t.library.preferences(for: .collection(collection.id)) == ListPreferences(sortLevels: title, viewMode: .grid))
    }

    @Test func aPerListSortFromBeforeCarriesOverUntilTheGlobalOneIsSet() throws {
        let t = try TestLibrary()
        for (key, raw, year) in [("reading", "title:asc", 2025), ("read", "pages:desc", 2026), ("all", "", 2027)] {
            let old = ListSettings()
            old.key = key
            old.sortLevelsRaw = raw
            old.updatedAt = date(year, 1, 1)
            t.context.insert(old)
        }
        #expect(t.library.preferences(for: .wantToRead).sortLevels.raw == "pages:desc")
        try t.library.setSortLevels(SortLevels(levels: [SortLevel(field: .year)]))
        #expect(t.library.preferences(for: .reading).sortLevels.raw == "year:asc")
        try t.library.resetSort()
        #expect(t.library.preferences(for: .read).sortLevels == .default)
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
        try t.library.setSortLevels(SortLevels(levels: [SortLevel(field: .pages)]))
        try t.library.resetSort()
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
