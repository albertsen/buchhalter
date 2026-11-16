import Foundation
import Testing
@testable import BuchhalterCore

struct ScanRoundTests {
    private func draft(status: DraftStatus?, collections: [UUID] = []) -> BookDraft {
        var draft = BookDraft()
        draft.status = status
        draft.collectionIDs = collections
        return draft
    }

    @Test func aFreshRoundHasNoPresetAndLeavesTheDefaults() {
        let round = ScanRound()
        var next = BookDraft()
        round.apply(to: &next)
        #expect(round.count == 0)
        #expect(round.preset == nil)
        #expect(round.lastAddedID == nil)
        #expect(next.status == .wantToRead)
        #expect(next.collectionIDs.isEmpty)
    }

    @Test func theFirstBooksChoicesApplyToTheSecond() {
        var round = ScanRound()
        let collection = UUID()
        round.recordAdded(draft(status: .read, collections: [collection]), id: UUID())
        var next = BookDraft()
        round.apply(to: &next)
        #expect(next.status == .read)
        #expect(next.collectionIDs == [collection])
    }

    @Test func aChangeOnTheSecondCarriesToTheThird() {
        var round = ScanRound()
        let first = UUID(), second = UUID()
        round.recordAdded(draft(status: .read, collections: [first]), id: UUID())
        round.recordAdded(draft(status: .wantToRead, collections: []), id: second)
        var third = BookDraft()
        round.apply(to: &third)
        #expect(third.status == .wantToRead)
        #expect(third.collectionIDs.isEmpty)
        #expect(round.count == 2)
        #expect(round.lastAddedID == second)
    }

    @Test func readingGetsTodayAsStartDate() {
        var round = ScanRound()
        round.recordAdded(draft(status: .reading), id: UUID())
        var next = BookDraft()
        round.apply(to: &next)
        #expect(next.status == .reading)
        #expect(next.startedAt == Calendar.current.startOfDay(for: .now))
    }

    @Test func aClearedStatusIsPresetToo() {
        var round = ScanRound()
        round.recordAdded(draft(status: nil), id: UUID())
        var next = BookDraft()
        round.apply(to: &next)
        #expect(next.status == nil)
    }
}
