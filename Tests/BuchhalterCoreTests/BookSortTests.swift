import Foundation
import Testing
@testable import BuchhalterCore

struct BookSortTests {
    private func key(
        _ title: String, author: String? = nil, year: Int? = nil, added: Int = 0,
        started: Date? = nil, finished: Date? = nil, rating: Int? = nil, pages: Int? = nil
    ) -> BookSortKey {
        BookSortKey(
            id: UUID(), authorSortName: author, titleKey: TextFolding.titleSortKey(title), year: year,
            addedAt: Date(timeIntervalSince1970: Double(added)), startedAt: started,
            finishedAt: finished, rating: rating, pages: pages
        )
    }

    private func order(_ keys: [BookSortKey], _ levels: SortLevels) -> [String] {
        keys.sorted { BookSorter.areInOrder($0, $1, by: levels) }.map(\.titleKey)
    }

    @Test func defaultLevelsAreAuthorThenYear() {
        #expect(SortLevels.default.raw == "author:asc,year:asc")
        let keys = [
            key("B2", author: "Mann, Thomas", year: 1924), key("B1", author: "Mann, Thomas", year: 1901),
            key("A", author: "Eliot, George", year: 1999),
        ]
        #expect(order(keys, .default) == ["A", "B1", "B2"])
    }

    @Test func authorsWithoutNameComeLastInBothDirections() {
        let keys = [key("None"), key("Z", author: "Zola"), key("A", author: "Adams")]
        #expect(order(keys, SortLevels(levels: [SortLevel(field: .author)])) == ["A", "Z", "None"])
        #expect(order(keys, SortLevels(levels: [SortLevel(field: .author, direction: .descending)])) == ["Z", "A", "None"])
    }

    @Test func everyFieldSortsBothWays() {
        let d1 = date(2020, 1, 1), d2 = date(2021, 1, 1)
        let a = key("a", year: 1900, added: 1, started: d1, finished: d1, rating: 1, pages: 100)
        let b = key("b", year: 2000, added: 2, started: d2, finished: d2, rating: 5, pages: 900)
        let none = key("c")
        for field in [SortField.year, .dateAdded, .dateStarted, .dateFinished, .rating, .pages] {
            let asc = order([b, none, a], SortLevels(levels: [SortLevel(field: field, direction: .ascending)]))
            let desc = order([a, none, b], SortLevels(levels: [SortLevel(field: field, direction: .descending)]))
            if field == .dateAdded {
                // Every book has an added date, so "c" (added at 0) is oldest.
                #expect(asc == ["c", "a", "b"])
                #expect(desc == ["b", "a", "c"])
            } else {
                #expect(asc == ["a", "b", "c"], "\(field) ascending")
                #expect(desc == ["b", "a", "c"], "\(field) descending")
            }
        }
        #expect(order([a, b], SortLevels(levels: [SortLevel(field: .title, direction: .descending)])) == ["b", "a"])
    }

    @Test func titleBreaksTiesAndIgnoresArticles() {
        let keys = [key("Der Zauberberg", author: "Mann"), key("Buddenbrooks", author: "Mann")]
        #expect(order(keys, .default) == ["Buddenbrooks", "Zauberberg"])
        let titles = order(keys, SortLevels(levels: [SortLevel(field: .title)]))
        #expect(titles == ["Buddenbrooks", "Zauberberg"])
    }

    @Test func readIn2026ExampleOrder() {
        let names = ["Woolf", "Mann", "Eliot", "Tolstoy", "Hesse", "Grass", "Fontane", "Johnson", "Nabokov", "Sebald", "Williams"]
        let keys = names.map { key($0, author: $0) }
        let sorted = keys.sorted { BookSorter.areInOrder($0, $1, by: .default) }.compactMap(\.authorSortName)
        #expect(sorted == ["Eliot", "Fontane", "Grass", "Hesse", "Johnson", "Mann", "Nabokov", "Sebald", "Tolstoy", "Williams", "Woolf"])
    }

    @Test func umlautAuthorSortsAmongA() {
        let keys = [key("x", author: "Böll"), key("y", author: "Ärger"), key("z", author: "Adams")]
        let sorted = keys.sorted { BookSorter.areInOrder($0, $1, by: .default) }.compactMap(\.authorSortName)
        #expect(sorted == ["Adams", "Ärger", "Böll"])
    }

    @Test func rawRoundTripAndRobustness() {
        let levels = SortLevels(levels: [SortLevel(field: .rating, direction: .descending), SortLevel(field: .pages)])
        #expect(SortLevels(raw: levels.raw) == levels)
        #expect(SortLevels(raw: "") == .default)
        #expect(SortLevels(raw: "nonsense:asc,rating:desc") == SortLevels(levels: [SortLevel(field: .rating, direction: .descending)]))
        #expect(SortLevels(raw: "rating:desc,rating:asc").levels.count == 1)
        #expect(SortLevels(raw: "rating:sideways").levels.first?.direction == .ascending)
    }

    @Test func editingLevels() {
        let levels = SortLevels.default
        #expect(levels.removing(at: 0) == levels)
        #expect(levels.removing(at: 1).levels.count == 1)
        #expect(levels.availableFields.count == 6)
        var full = levels
        while full.canAdd { full = full.adding() }
        #expect(full.levels.count == SortField.allCases.count)
        #expect(full.adding() == full)
        let swapped = levels.setting(field: .author, at: 1)
        #expect(swapped.levels.map(\.field) == [.author])
        #expect(levels.setting(field: .title, at: 1).levels.map(\.field) == [.author, .title])
    }

    @MainActor
    @Test func sortsModelBooks() throws {
        let t = try TestLibrary()
        try t.add("Der Zauberberg", by: ["Thomas Mann"], year: 1924)
        try t.add("Buddenbrooks", by: ["Thomas Mann"], year: 1901)
        try t.add("Stoner", by: ["John Williams"])
        try t.add("No Author")
        let sorted = BookSorter.sorted(t.library.fetchBooks(), by: .default).map(\.title)
        #expect(sorted == ["Buddenbrooks", "Der Zauberberg", "Stoner", "No Author"])
    }
}
