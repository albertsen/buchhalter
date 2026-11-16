import Foundation
import Testing
@testable import BuchhalterCore

struct SyncStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsUpToDateWithoutADate() {
        let state = SyncState()
        #expect(state.box == .upToDate(lastSynced: nil))
        #expect(state.sidebarLine == nil)
    }

    @Test func aRunningEventShowsSyncingAndEndsAsUpToDateWithItsDate() {
        var state = SyncState()
        state.eventStarted(.download)
        #expect(state.box == .syncing(firstTransfer: false))
        state.eventEnded(.download, success: true, at: at(5))
        #expect(state.box == .upToDate(lastSynced: at(5)))
        #expect(state.lastSynced == at(5))
    }

    @Test func everydayEventsNeverShowTheSidebarLine() {
        var state = SyncState()
        for kind in SyncEventKind.allCases {
            state.eventStarted(kind)
            #expect(state.sidebarLine == nil)
            state.eventEnded(kind, success: true, at: at(1))
        }
        #expect(state.sidebarLine == nil)
    }

    @Test func lastSyncedIsTheLastSuccessfulEnd() {
        var state = SyncState()
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: true, at: at(10))
        state.eventStarted(.download)
        state.eventEnded(.download, success: false, error: .other("x"), at: at(20))
        #expect(state.lastSynced == at(10))
    }

    // MARK: Problems

    @Test func signedOutIsAProblemUntilSigningIn() {
        var state = SyncState()
        state.account(.unavailable)
        #expect(state.box == .problem(.notSignedIn))
        #expect(state.sidebarLine == .problem)
        state.account(.available)
        #expect(state.box == .upToDate(lastSynced: nil))
        #expect(state.sidebarLine == nil)
    }

    @Test func eventsWhileSignedOutKeepTheProblem() {
        var state = SyncState()
        state.account(.unavailable)
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: false, error: .notAuthenticated, at: at(1))
        #expect(state.box == .problem(.notSignedIn))
    }

    @Test func anAvailableAccountThatRefusesTheAppIsTurnedOffForIt() {
        var state = SyncState()
        state.account(.available)
        state.eventStarted(.setup)
        state.eventEnded(.setup, success: false, error: .notAuthenticated, at: at(1))
        #expect(state.box == .problem(.turnedOffForApp))
    }

    @Test func quotaExceededIsStorageFull() {
        var state = SyncState()
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: false, error: .quotaExceeded, at: at(1))
        #expect(state.box == .problem(.storageFull))
        #expect(state.sidebarLine == .problem)
    }

    @Test func anotherErrorIsFailedWithItsMessage() {
        var state = SyncState()
        state.eventStarted(.download)
        state.eventEnded(.download, success: false, error: .other("The network is down"), at: at(1))
        #expect(state.box == .problem(.failed("The network is down")))
    }

    @Test func aSuccessfulEventClearsAProblem() {
        var state = SyncState()
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: false, error: .quotaExceeded, at: at(1))
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: true, at: at(2))
        #expect(state.box == .upToDate(lastSynced: at(2)))
    }

    @Test func aProblemOutranksSyncing() {
        var state = SyncState()
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: false, error: .other("x"), at: at(1))
        state.eventStarted(.download)
        #expect(state.box == .problem(.failed("x")))
    }

    // MARK: First transfer

    @Test func theFirstUploadShowsTheLineAndEndsOnlyAfterTheQuietPeriod() {
        var state = SyncState()
        state.firstUploadBegan(at: t0)
        #expect(state.box == .syncing(firstTransfer: true))
        #expect(state.sidebarLine == .uploading)

        state.eventStarted(.upload)
        state.eventEnded(.upload, success: true, at: at(30))
        // Too early: 10 s after the last export.
        state.quietPeriodPassed(.upload, at: at(40))
        #expect(state.firstTransfer == .upload)
        // A new export starts: the period begins again.
        state.eventStarted(.upload)
        state.quietPeriodPassed(.upload, at: at(100))
        #expect(state.firstTransfer == .upload)
        state.eventEnded(.upload, success: true, at: at(110))
        state.quietPeriodPassed(.upload, at: at(131))
        #expect(state.firstTransfer == nil)
        #expect(state.box == .upToDate(lastSynced: at(110)))
        #expect(state.sidebarLine == nil)
    }

    @Test func aDownloadEventDoesNotEndTheFirstUpload() {
        var state = SyncState()
        state.firstUploadBegan(at: t0)
        state.eventStarted(.download)
        state.eventEnded(.download, success: true, at: at(5))
        state.quietPeriodPassed(.download, at: at(100))
        #expect(state.firstTransfer == .upload)
    }

    @Test func aFailedEventKeepsTheFirstTransferGoing() {
        var state = SyncState()
        state.firstUploadBegan(at: t0)
        state.eventStarted(.upload)
        state.eventEnded(.upload, success: false, error: .other("x"), at: at(5))
        state.quietPeriodPassed(.upload, at: at(100))
        #expect(state.firstTransfer == .upload)
        #expect(state.sidebarLine == .problem)
    }

    @Test func aRelaunchedUploadWithNothingToSendEndsAfterTheQuietPeriod() {
        var state = SyncState(firstTransfer: .upload, lastSynced: t0)
        state.firstUploadBegan(at: at(1000))
        state.quietPeriodPassed(.upload, at: at(1010))
        #expect(state.firstTransfer == .upload)
        state.quietPeriodPassed(.upload, at: at(1021))
        #expect(state.firstTransfer == nil)
    }

    @Test func theFirstDownloadHasItsOwnLine() {
        var state = SyncState()
        state.firstDownloadBegan(at: t0)
        #expect(state.sidebarLine == .downloading)
        state.eventStarted(.download)
        state.eventEnded(.download, success: true, at: at(3))
        state.quietPeriodPassed(.download, at: at(24))
        #expect(state.sidebarLine == nil)
    }
}

struct SyncMessagesTests {
    private let messages = SyncMessages(locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Europe/Berlin") ?? .current)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = messages.timeZone
        return calendar
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) ?? .distantPast
    }

    @Test func todayYesterdayAndOlderDates() {
        let now = date(2026, 11, 16, 15, 0)
        #expect(messages.lastSynced(date(2026, 11, 16, 14, 32), now: now) == "Today, 14:32")
        #expect(messages.lastSynced(date(2026, 11, 15, 9, 10), now: now) == "Yesterday, 09:10")
        #expect(messages.lastSynced(date(2026, 11, 3, 18, 5), now: now) == "3 Nov 2026, 18:05")
    }

    @Test func theCountsLineJoinsBooksAndSize() {
        #expect(messages.inICloud(books: 79, bytes: 42_000_000).hasPrefix("79 books · "))
        #expect(messages.inICloud(books: 79, bytes: 42_000_000).hasSuffix(" MB"))
    }

    @Test func everyProblemHasItsMessageAndButton() {
        #expect(messages.message(for: .notSignedIn).hasPrefix("Sign in to iCloud"))
        #expect(messages.message(for: .turnedOffForApp).hasPrefix("iCloud is turned off"))
        #expect(messages.message(for: .storageFull).hasPrefix("Your iCloud storage is full"))
        #expect(messages.message(for: .failed("Boom")).hasPrefix("iCloud sync stopped: Boom."))
        #expect(messages.button(for: .notSignedIn) == "Open System Settings…")
        #expect(messages.button(for: .turnedOffForApp) == "Open System Settings…")
        #expect(messages.button(for: .storageFull) == "Manage Storage…")
        #expect(messages.button(for: .failed("x")) == nil)
    }

    @Test func theSidebarLines() {
        #expect(messages.sidebarLine(.uploading) == "Uploading your library to iCloud…")
        #expect(messages.sidebarLine(.downloading) == "Getting your library from iCloud…")
        #expect(messages.sidebarLine(.problem) == "iCloud sync isn't working")
    }
}
