import Foundation

/// Every sentence the sync status shows, as catalog keys. The locale is
/// explicit so tests can check both languages; in the test runner (no
/// catalog) the values are the English keys.
public struct SyncMessages: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    // MARK: Status

    public var upToDate: String { String(localized: "Up to date", locale: locale) }
    public var syncing: String { String(localized: "Syncing with iCloud…", locale: locale) }
    public var notYet: String { String(localized: "Not yet", locale: locale) }

    /// "Today, 14:32", "Yesterday, 09:10", "3 Nov 2026, 18:05".
    public func lastSynced(_ date: Date, now: Date = .now) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let time = date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today, \(time)", locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday, \(time)", locale: locale)
        }
        let day = BookFormatting(locale: locale, timeZone: timeZone).day(date)
        return String(localized: "\(day), \(time)", locale: locale)
    }

    /// "79 books · 42 MB". The size is the local store and covers, which iCloud
    /// mirrors; CloudKit reports no usage of its own.
    public func inICloud(books: Int, bytes: Int64) -> String {
        let count = BookFormatting(locale: locale, timeZone: timeZone).bookCount(books)
        let size = Self.size(bytes, locale: locale)
        return String(localized: "\(count) · \(size)", locale: locale)
    }

    static func size(_ bytes: Int64, locale: Locale) -> String {
        bytes.formatted(.byteCount(style: .file).locale(locale))
    }

    // MARK: Problems

    public func message(for problem: SyncProblem) -> String {
        switch problem {
        case .notSignedIn:
            String(localized: "Sign in to iCloud to sync. Until then the library stays on this Mac only.", locale: locale)
        case .turnedOffForApp:
            String(localized: "iCloud is turned off for Buchhalter. The library stays on this Mac only and is not protected if the Mac is lost.", locale: locale)
        case .storageFull:
            String(localized: "Your iCloud storage is full. New changes stay on this Mac and sync once there is space.", locale: locale)
        case .failed(let message):
            String(localized: "iCloud sync stopped: \(message). Your changes are kept on this Mac. Buchhalter tries again at the next launch.", locale: locale)
        }
    }

    /// The button beside a message; nil when there is none.
    public func button(for problem: SyncProblem) -> String? {
        switch problem {
        case .notSignedIn, .turnedOffForApp: String(localized: "Open System Settings…", locale: locale)
        case .storageFull: String(localized: "Manage Storage…", locale: locale)
        case .failed: nil
        }
    }

    // MARK: Sidebar

    public func sidebarLine(_ line: SyncSidebarLine) -> String {
        switch line {
        case .uploading: String(localized: "Uploading your library to iCloud…", locale: locale)
        case .downloading: String(localized: "Getting your library from iCloud…", locale: locale)
        case .problem: String(localized: "iCloud sync isn't working", locale: locale)
        }
    }

    // MARK: One-time sheet

    /// "All 79 books are going to iCloud, with their readings, collections and covers. …"
    public func noticeCount(_ count: Int) -> String {
        String(localized: "All \(count) books are going to iCloud, with their readings, collections and covers. You can keep working meanwhile.", locale: locale)
    }
}
