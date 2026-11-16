import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

/// Two devices are two contexts that never saw each other's insert.
@MainActor
struct SyncDuplicateTests {
    private func author(_ name: String, sortName: String? = nil, id: String, in context: ModelContext) -> Author {
        let author = Author()
        author.id = UUID(uuidString: id) ?? UUID()
        author.name = name
        author.sortName = sortName ?? AuthorName.guessSortName(name)
        context.insert(author)
        return author
    }

    private func book(_ title: String, by authors: [Author], isbn: String? = nil, in context: ModelContext) -> Book {
        let book = Book()
        book.title = title
        book.isbn13 = isbn
        context.insert(book)
        for (position, author) in authors.enumerated() {
            let authorship = Authorship()
            authorship.position = position
            context.insert(authorship)
            authorship.book = book
            authorship.author = author
        }
        return book
    }

    private let low = "00000000-0000-0000-0000-000000000001"
    private let high = "00000000-0000-0000-0000-000000000002"

    @Test func twoAuthorsWithOneNameBecomeOneAndTheBooksKeepTheirAuthorOrder() throws {
        let t = try TestLibrary()
        let c = t.context
        let first = author("Thomas Mann", id: high, in: c)
        let second = author("thomas  mann", id: low, in: c)
        let other = author("Erika Mann", id: "00000000-0000-0000-0000-000000000009", in: c)
        let a = book("Buddenbrooks", by: [first, other], in: c)
        let b = book("Der Zauberberg", by: [second], in: c)
        try c.save()

        let removed = try t.library.mergeSyncDuplicates()

        #expect(removed == 1)
        let authors = try c.fetch(FetchDescriptor<Author>())
        #expect(authors.count == 2)
        // The smallest id survives, whichever object it was.
        let survivor = try #require(authors.first { AuthorName.matchKey($0.name) == "thomas mann" })
        #expect(survivor.id.uuidString == low)
        #expect(a.orderedAuthors.map(\.name) == [survivor.name, "Erika Mann"])
        #expect(b.orderedAuthors.map(\.id) == [survivor.id])
    }

    @Test func aCorrectedSortNameWins() throws {
        let t = try TestLibrary()
        let c = t.context
        _ = author("Ursula K. Le Guin", sortName: "Guin, Ursula K. Le", id: low, in: c)
        _ = author("Ursula K. Le Guin", sortName: "Le Guin, Ursula K.", id: high, in: c)
        try c.save()
        // The guess for the name is "Guin, Ursula K. Le", so the other one was corrected by the user.
        #expect(AuthorName.guessSortName("Ursula K. Le Guin") == "Guin, Ursula K. Le")

        try t.library.mergeSyncDuplicates()

        let authors = try c.fetch(FetchDescriptor<Author>())
        #expect(authors.count == 1)
        #expect(authors[0].sortName == "Le Guin, Ursula K.")
        #expect(authors[0].id.uuidString == low)
    }

    @Test func aBookWithBothSpellingsListsTheAuthorOnce() throws {
        let t = try TestLibrary()
        let c = t.context
        let first = author("Thomas Mann", id: low, in: c)
        let second = author("Thomas Mann", id: high, in: c)
        let b = book("Essays", by: [first, second], in: c)
        try c.save()

        try t.library.mergeSyncDuplicates()

        #expect(b.orderedAuthors.count == 1)
        #expect(try c.fetchCount(FetchDescriptor<Authorship>()) == 1)
    }

    @Test func twoCollectionsWithOneNameBecomeOneWithTheUnionOfBooksAndTheEarlierNoteAndPlace() throws {
        let t = try TestLibrary()
        let c = t.context
        let a = book("A", by: [], in: c)
        let b = book("B", by: [], in: c)
        let shared = book("Shared", by: [], in: c)
        let early = Collection()
        early.name = "Read in 2027"
        early.note = "First note"
        early.sortIndex = 1
        early.createdAt = date(2027, 1, 1)
        early.books = [a, shared]
        let late = Collection()
        late.name = "read in 2027"
        late.note = "Second note"
        late.sortIndex = 5
        late.createdAt = date(2027, 2, 1)
        late.books = [b, shared]
        c.insert(early)
        c.insert(late)
        try c.save()

        try t.library.mergeSyncDuplicates()

        let collections = try c.fetch(FetchDescriptor<Collection>())
        #expect(collections.count == 1)
        let merged = try #require(collections.first)
        #expect(merged.createdAt == date(2027, 1, 1))
        #expect(merged.note == "First note")
        #expect(merged.sortIndex == 1)
        #expect(Set((merged.books ?? []).map(\.title)) == ["A", "B", "Shared"])
        #expect((merged.books ?? []).count == 3)
        #expect(try c.fetchCount(FetchDescriptor<Book>()) == 3)
    }

    @Test func settingsRowsWithOneKeyKeepTheNewest() throws {
        let t = try TestLibrary()
        for (year, raw) in [(2025, "title:asc"), (2027, "year:desc"), (2026, "pages:asc")] {
            let row = ListSettings()
            row.key = ListSettings.sortKey
            row.sortLevelsRaw = raw
            row.updatedAt = date(year, 1, 1)
            t.context.insert(row)
        }
        try t.context.save()

        try t.library.mergeSyncDuplicates()

        let rows = try t.context.fetch(FetchDescriptor<ListSettings>())
        #expect(rows.map(\.sortLevelsRaw) == ["year:desc"])
    }

    @Test func twoBooksWithOneISBNStayTwo() throws {
        let t = try TestLibrary()
        _ = book("Copy 1", by: [], isbn: "9783596294310", in: t.context)
        _ = book("Copy 2", by: [], isbn: "9783596294310", in: t.context)
        try t.context.save()

        #expect(try t.library.mergeSyncDuplicates() == 0)

        #expect(try t.context.fetchCount(FetchDescriptor<Book>()) == 2)
    }

    @Test func runningTheMergeTwiceChangesNothing() throws {
        let t = try TestLibrary()
        let c = t.context
        _ = author("Thomas Mann", id: low, in: c)
        _ = author("Thomas Mann", id: high, in: c)
        let one = Collection()
        one.name = "X"
        let two = Collection()
        two.name = "X"
        c.insert(one)
        c.insert(two)
        try c.save()

        #expect(try t.library.mergeSyncDuplicates() == 2)
        #expect(try t.library.mergeSyncDuplicates() == 0)
    }

    @Test func theSurvivorIsTheSameWhicheverContextMerges() throws {
        // Two devices holding the same two authors merge on their own and must pick the same one.
        var survivors: [UUID] = []
        for order in [[low, high], [high, low]] {
            let t = try TestLibrary()
            for id in order { _ = author("Thomas Mann", id: id, in: t.context) }
            try t.context.save()
            try t.library.mergeSyncDuplicates()
            survivors.append(try #require(try t.context.fetch(FetchDescriptor<Author>()).first).id)
        }
        #expect(survivors[0] == survivors[1])
        #expect(survivors[0].uuidString == low)
    }

    @Test func nothingToMergeIsNotAnError() throws {
        let t = try TestLibrary()
        try t.add("Solo", by: ["Thomas Mann"])
        #expect(try t.library.mergeSyncDuplicates() == 0)
    }
}
