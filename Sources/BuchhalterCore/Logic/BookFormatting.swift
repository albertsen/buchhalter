import Foundation

/// Locale-aware text for books and readings. Every sentence is a catalog key
/// with placeholders; only the pieces (dates, numbers) are formatted here.
/// The locale is explicit so tests can check both languages.
public struct BookFormatting: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    // MARK: Pieces

    /// "3 Oct 2026" / "3. Okt. 2026".
    public func day(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(.abbreviated).year())
    }

    /// "12 Jan – 2 Mar 2019" / "12. Jan. – 2. März 2019".
    public func range(_ start: Date, _ end: Date) -> String {
        guard start != end else { return day(start) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let style = Date.IntervalFormatStyle(
            locale: locale, calendar: calendar, timeZone: timeZone
        ).day().month(.abbreviated).year()
        return (start..<end).formatted(style)
    }

    /// 1901 prints as "1901", never "1.901".
    public func year(_ year: Int) -> String { String(year) }

    public func languageName(_ code: String) -> String {
        locale.localizedString(forLanguageCode: code)?.localizedCapitalizedFirst(locale: locale) ?? code
    }

    // MARK: Sentences

    /// "1901 · 759 pages · German · ISBN 978-…", and for a translation
    /// "1994 · 176 pages · German (original: Japanese) · ISBN 978-…".
    public func metaLine(_ book: Book) -> String {
        var parts: [String] = []
        if let value = book.year { parts.append(year(value)) }
        if let pages = book.pageCount { parts.append(pageCount(pages)) }
        switch (book.language, book.originalLanguage) {
        case let (code?, original?) where original != code:
            parts.append(String(localized: "\(languageName(code)) (original: \(languageName(original)))", locale: locale))
        case let (nil, original?):
            parts.append(String(localized: "Original: \(languageName(original))", locale: locale))
        case let (code?, _):
            parts.append(languageName(code))
        case (nil, nil):
            break
        }
        if let isbn = book.isbnText, !isbn.isEmpty { parts.append(String(localized: "ISBN \(isbn)", locale: locale)) }
        return parts.joined(separator: " · ")
    }

    public func pageCount(_ pages: Int) -> String {
        String(localized: "\(pages) pages", locale: locale)
    }

    public func bookCount(_ count: Int) -> String {
        count == 0 ? String(localized: "No books", locale: locale) : String(localized: "\(count) books", locale: locale)
    }

    /// The row's status line: "Started 3 Oct 2026", "Finished 2 Mar 2019", "Abandoned 5 Nov 2026".
    public func statusLine(_ reading: Reading) -> String? {
        let status = ReadingStatus(raw: reading.statusRaw)
        switch status {
        case .wantToRead:
            return nil
        case .reading:
            guard let start = reading.startedAt else { return String(localized: "Reading", locale: locale) }
            return String(localized: "Started \(day(start))", locale: locale)
        case .finished:
            guard let end = reading.endedAt else { return String(localized: "Finished", locale: locale) }
            return String(localized: "Finished \(day(end))", locale: locale)
        case .abandoned:
            guard let end = reading.endedAt else { return String(localized: "Abandoned", locale: locale) }
            return String(localized: "Abandoned \(day(end))", locale: locale)
        }
    }

    /// The detail badge: "Reading since 3 Oct 2026", "Finished 2 Mar 2019", "Abandoned", "Want to Read".
    public func badge(_ reading: Reading) -> String {
        let status = ReadingStatus(raw: reading.statusRaw)
        switch status {
        case .wantToRead:
            return String(localized: "Want to Read", locale: locale)
        case .reading:
            guard let start = reading.startedAt else { return String(localized: "Reading", locale: locale) }
            return String(localized: "Reading since \(day(start))", locale: locale)
        case .finished:
            guard let end = reading.endedAt else { return String(localized: "Finished", locale: locale) }
            return String(localized: "Finished \(day(end))", locale: locale)
        case .abandoned:
            return String(localized: "Abandoned", locale: locale)
        }
    }

    /// The Readings section's line: "Started 3 Oct 2026", "12 Jan – 2 Mar 2019", "Abandoned 5 Nov 2026".
    public func readingSummary(_ reading: Reading) -> String {
        let status = ReadingStatus(raw: reading.statusRaw)
        switch status {
        case .wantToRead:
            return String(localized: "Want to Read", locale: locale)
        case .reading:
            guard let start = reading.startedAt else { return String(localized: "Reading", locale: locale) }
            return String(localized: "Started \(day(start))", locale: locale)
        case .finished:
            switch (reading.startedAt, reading.endedAt) {
            case let (start?, end?): return range(start, end)
            case let (nil, end?): return day(end)
            default: return String(localized: "Finished", locale: locale)
            }
        case .abandoned:
            switch (reading.startedAt, reading.endedAt) {
            case let (start?, end?): return String(localized: "Abandoned \(range(start, end))", locale: locale)
            case let (nil, end?): return String(localized: "Abandoned \(day(end))", locale: locale)
            default: return String(localized: "Abandoned", locale: locale)
            }
        }
    }

    /// "Sort: Author, Year".
    public func sortButtonLabel(_ levels: SortLevels) -> String {
        let names = levels.levels.map { String(localized: $0.field.shortName.withLocale(locale)) }
        let list = names.formatted(.list(type: .and, width: .narrow).locale(locale))
        return String(localized: "Sort: \(list)", locale: locale)
    }
}

private extension LocalizedStringResource {
    func withLocale(_ locale: Locale) -> LocalizedStringResource {
        var copy = self
        copy.locale = locale
        return copy
    }
}

private extension String {
    func localizedCapitalizedFirst(locale: Locale) -> String {
        guard let first else { return self }
        return String(first).uppercased(with: locale) + dropFirst()
    }
}
