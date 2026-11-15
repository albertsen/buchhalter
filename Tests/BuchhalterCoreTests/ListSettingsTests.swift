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

    @Test func perListAndPerCollection() throws {
        let t = try TestLibrary()
        let collection = try t.library.createCollection(named: "A")
        let title = SortLevels(levels: [SortLevel(field: .title)])
        let rating = SortLevels(levels: [SortLevel(field: .rating, direction: .descending)])
        try t.library.setSortLevels(title, for: .reading)
        try t.library.setSortLevels(rating, for: .collection(collection.id))
        try t.library.setViewMode(.grid, for: .collection(collection.id))
        #expect(t.library.preferences(for: .reading) == ListPreferences(sortLevels: title, viewMode: .list))
        #expect(t.library.preferences(for: .collection(collection.id)) == ListPreferences(sortLevels: rating, viewMode: .grid))
        #expect(t.library.preferences(for: .all) == .default)
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
