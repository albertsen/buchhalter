import CoreGraphics
import Foundation
import Testing
@testable import BuchhalterCore

@MainActor
struct ScanSessionTests {
    private let isbnCode = "9783596294312"
    private let priceCode = "4006381333931"
    private let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.1)
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    private func detection(_ payload: String) -> ScanSession.Detection {
        ScanSession.Detection(payload: payload, box: box)
    }

    private func see(
        _ session: inout ScanSession, _ payload: String, at seconds: Double,
        duplicate: (String) -> DuplicateIndex.Entry? = { _ in nil }
    ) -> [ScanSession.Effect] {
        session.handle(.detections([detection(payload)], at: at(seconds)), duplicate: duplicate)
    }

    private var isbn: ISBN {
        if case .valid(let value) = ISBN.parse(isbnCode) { return value }
        preconditionFailure("test ISBN")
    }

    private func entry() throws -> (DuplicateIndex.Entry, TestLibrary) {
        let t = try TestLibrary()
        try t.add("Buddenbrooks", by: ["Thomas Mann"], year: 1901, isbn: isbnCode)
        let found = try #require(DuplicateIndex(books: t.library.fetchBooks()).match(isbn13: isbnCode))
        return (found, t)
    }

    // MARK: Confirming

    @Test func oneFrameNeverConfirms() {
        var session = ScanSession()
        #expect(see(&session, isbnCode, at: 0).isEmpty)
        #expect(session.state == .looking)
    }

    @Test func twoFramesWithinHalfASecondConfirm() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        let effects = see(&session, isbnCode, at: 0.4)
        #expect(effects == [.playSound])
        #expect(session.state == .found(isbn, box: box))
    }

    @Test func twoFramesSixTenthsApartDoNot() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        #expect(see(&session, isbnCode, at: 0.6).isEmpty)
        #expect(session.state == .looking)
        // The late frame counts as a first one.
        #expect(see(&session, isbnCode, at: 0.8) == [.playSound])
    }

    @Test func twoDifferentBarcodesInOneFrameStillConfirmTheISBN() {
        var session = ScanSession()
        let both = [detection(priceCode), detection(isbnCode)]
        _ = session.handle(.detections(both, at: at(0)))
        let effects = session.handle(.detections(both, at: at(0.1)))
        #expect(effects == [.playSound])
        #expect(session.hint == nil)
    }

    @Test func misreadsAndOtherPayloadsAreIgnored() {
        var session = ScanSession()
        for payload in ["9783596294313", "https://example.com", "12345"] {
            _ = see(&session, payload, at: 0)
            _ = see(&session, payload, at: 0.1)
        }
        #expect(session.state == .looking)
        #expect(session.hint == nil)
    }

    // MARK: Sound and editor

    @Test func theSoundFiresOncePerRead() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        #expect(see(&session, isbnCode, at: 0.1) == [.playSound])
        #expect(see(&session, isbnCode, at: 0.2).isEmpty)
        #expect(see(&session, isbnCode, at: 0.3).isEmpty)
    }

    @Test func theEditorOpensHalfASecondAfterTheRead() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        _ = see(&session, isbnCode, at: 0.1)
        #expect(session.handle(.tick(at(0.4))).isEmpty)
        #expect(session.state == .found(isbn, box: box))
        #expect(session.handle(.tick(at(0.6))) == [.openEditor(isbn)])
        #expect(session.state == .paused)
        #expect(session.handle(.tick(at(0.8))).isEmpty)
    }

    @Test func theGreenFrameFollowsTheBarcode() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        _ = see(&session, isbnCode, at: 0.1)
        let moved = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)
        _ = session.handle(.detections([.init(payload: isbnCode, box: moved)], at: at(0.2)))
        #expect(session.state == .found(isbn, box: moved))
    }

    // MARK: Not an ISBN

    @Test func aPriceCodeShowsAnAmberHintForFourSeconds() {
        var session = ScanSession()
        _ = see(&session, priceCode, at: 0)
        #expect(see(&session, priceCode, at: 0.1).isEmpty)
        #expect(session.hint?.display == "4 006381 333931")
        #expect(session.state == .looking)
        _ = session.handle(.tick(at(3.9)))
        #expect(session.hint != nil)
        _ = session.handle(.tick(at(4.2)))
        #expect(session.hint == nil)
    }

    @Test func theSameCodeDoesNotRestartTheTimer() {
        var session = ScanSession()
        _ = see(&session, priceCode, at: 0)
        _ = see(&session, priceCode, at: 0.1)
        let until = session.hint?.until
        for step in stride(from: 0.5, through: 3.5, by: 0.5) { _ = see(&session, priceCode, at: step) }
        #expect(session.hint?.until == until)
    }

    @Test func aCodeHeldInViewShowsItsHintOnlyOnce() {
        var session = ScanSession()
        var shown = 0
        var wasShowing = false
        for step in stride(from: 0.0, through: 10.0, by: 0.1) {
            _ = see(&session, priceCode, at: step)
            _ = session.handle(.tick(at(step)))
            let showing = session.hint != nil
            if showing && !wasShowing { shown += 1 }
            wasShowing = showing
        }
        #expect(shown == 1)
    }

    @Test func theHintComesBackWhenTheCodeComesBack() {
        var session = ScanSession()
        _ = see(&session, priceCode, at: 0)
        _ = see(&session, priceCode, at: 0.1)
        _ = session.handle(.tick(at(5)))
        #expect(session.hint == nil)
        _ = see(&session, priceCode, at: 9)
        _ = see(&session, priceCode, at: 9.1)
        #expect(session.hint != nil)
    }

    @Test func aNewBarcodeReplacesTheHint() {
        var session = ScanSession()
        let other = "9771234567003"
        _ = see(&session, priceCode, at: 0)
        _ = see(&session, priceCode, at: 0.1)
        // The hint stays while the next code is only seen once.
        _ = see(&session, other, at: 1)
        #expect(session.hint?.display == "4 006381 333931")
        _ = see(&session, other, at: 1.1)
        #expect(session.hint?.display == "9 771234 567003")
    }

    @Test func anISBNReplacesTheHint() {
        var session = ScanSession()
        _ = see(&session, priceCode, at: 0)
        _ = see(&session, priceCode, at: 0.1)
        _ = see(&session, isbnCode, at: 1)
        _ = see(&session, isbnCode, at: 1.1)
        #expect(session.hint == nil)
    }

    // MARK: Duplicates

    @Test func aDuplicateGivesTheBannerNotTheEditor() throws {
        let (found, t) = try entry()
        _ = t
        var session = ScanSession()
        let lookup: (String) -> DuplicateIndex.Entry? = { $0 == isbnCode ? found : nil }
        _ = see(&session, isbnCode, at: 0, duplicate: lookup)
        #expect(see(&session, isbnCode, at: 0.1, duplicate: lookup) == [.playSound])
        #expect(session.handle(.tick(at(0.7)), duplicate: lookup).isEmpty)
        #expect(session.state == .duplicate(found, isbn))
        // The camera keeps running but a banner is up: detections change nothing.
        #expect(see(&session, priceCode, at: 1, duplicate: lookup).isEmpty)
        #expect(see(&session, priceCode, at: 1.1, duplicate: lookup).isEmpty)
        #expect(session.state == .duplicate(found, isbn))
        #expect(session.hint == nil)
    }

    @Test func scanAnotherReturnsToLooking() throws {
        let (found, t) = try entry()
        _ = t
        var session = ScanSession()
        let lookup: (String) -> DuplicateIndex.Entry? = { _ in found }
        _ = see(&session, isbnCode, at: 0, duplicate: lookup)
        _ = see(&session, isbnCode, at: 0.1, duplicate: lookup)
        _ = session.handle(.tick(at(0.7)), duplicate: lookup)
        #expect(session.handle(.dismissDuplicate).isEmpty)
        #expect(session.state == .looking)
        // The same book can be scanned again.
        _ = see(&session, isbnCode, at: 2, duplicate: lookup)
        #expect(see(&session, isbnCode, at: 2.1, duplicate: lookup) == [.playSound])
    }

    @Test func addAnywayOpensTheEditor() throws {
        let (found, t) = try entry()
        _ = t
        var session = ScanSession()
        let lookup: (String) -> DuplicateIndex.Entry? = { _ in found }
        _ = see(&session, isbnCode, at: 0, duplicate: lookup)
        _ = see(&session, isbnCode, at: 0.1, duplicate: lookup)
        _ = session.handle(.tick(at(0.7)), duplicate: lookup)
        #expect(session.handle(.addAnyway) == [.openEditor(isbn)])
        #expect(session.state == .paused)
        // Without a banner there is nothing to add anyway.
        #expect(session.handle(.addAnyway).isEmpty)
    }

    // MARK: Filling a field

    @Test func fillModeFillsAtOnceAndNeverChecksDuplicates() throws {
        let (found, t) = try entry()
        _ = t
        var session = ScanSession(mode: .fillISBN)
        let lookup: (String) -> DuplicateIndex.Entry? = { _ in found }
        _ = see(&session, isbnCode, at: 0, duplicate: lookup)
        #expect(see(&session, isbnCode, at: 0.1, duplicate: lookup) == [.playSound, .fillField(isbn)])
        #expect(session.handle(.tick(at(1)), duplicate: lookup).isEmpty)
        #expect(session.state == .found(isbn, box: box))
    }

    @Test func fillModeStillShowsTheHint() {
        var session = ScanSession(mode: .fillISBN)
        _ = see(&session, priceCode, at: 0)
        _ = see(&session, priceCode, at: 0.1)
        #expect(session.hint != nil)
    }

    // MARK: Pause and resume

    @Test func pauseIgnoresDetections() {
        var session = ScanSession()
        _ = session.handle(.pause)
        _ = see(&session, isbnCode, at: 0)
        #expect(see(&session, isbnCode, at: 0.1).isEmpty)
        #expect(session.state == .paused)
    }

    @Test func resumeClearsTheLastCodeSoTheSameBookCanBeScannedAgain() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        _ = see(&session, isbnCode, at: 0.1)
        _ = session.handle(.tick(at(0.7)))
        #expect(session.state == .paused)
        _ = session.handle(.resume)
        #expect(session.state == .looking)
        // One frame is not enough, even though the code was just read.
        #expect(see(&session, isbnCode, at: 1).isEmpty)
        #expect(see(&session, isbnCode, at: 1.1) == [.playSound])
    }

    @Test func resumeWithoutPauseChangesNothing() {
        var session = ScanSession()
        _ = see(&session, isbnCode, at: 0)
        _ = see(&session, isbnCode, at: 0.1)
        _ = session.handle(.resume)
        #expect(session.state == .found(isbn, box: box))
    }
}
