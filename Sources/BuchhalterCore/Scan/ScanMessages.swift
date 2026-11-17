import Foundation

/// The sentences the scan sheet shows over the picture and under it, as
/// catalog keys with placeholders, like `LookupMessages`. The locale is
/// explicit so tests can check both languages; in the test runner (no
/// catalog) the values are the English keys.
public struct ScanMessages: Sendable {
    public var locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    // MARK: Over the picture

    public func looking() -> String {
        String(localized: "Looking for a barcode…", locale: locale)
    }

    /// "ISBN 978-3-596-29431-2".
    public func isbnRead(_ isbn: ISBN) -> String {
        String(localized: "ISBN \(isbn.hyphenated)", locale: locale)
    }

    /// The amber hint for a barcode that is not an ISBN; `display` is "4 006381 333931".
    public func notISBN(display: String) -> String {
        String(localized: "This barcode isn't an ISBN (\(display)). Look for the one that starts with 978 or 979.", locale: locale)
    }

    // MARK: Under the picture

    /// "Already in your library: Buddenbrooks (1901)", the label of Add Book's banner.
    public func alreadyInLibrary(_ entry: DuplicateIndex.Entry) -> String {
        String(localized: "Already in your library: \(entry.label)", locale: locale)
    }

    // MARK: No camera

    public func noAccessTitle() -> String {
        String(localized: "Buchhalter can't use the camera", locale: locale)
    }

    public func noAccessMessage() -> String {
        String(localized: "Allow camera access for Buchhalter in System Settings → Privacy & Security → Camera.", locale: locale)
    }

    public func noCameraTitle() -> String {
        String(localized: "No camera found", locale: locale)
    }

    public func noCameraMessage() -> String {
        String(localized: "Connect a camera or put an iPhone near this Mac. You can also type the ISBN.", locale: locale)
    }

    // MARK: iPhone and iPad

    public func pointAtBarcode() -> String {
        String(localized: "Point the camera at the barcode on the back of the book.", locale: locale)
    }

    public func noAccessMessagePhone() -> String {
        String(localized: "Allow camera access for Buchhalter in Settings.", locale: locale)
    }

    /// "3 other editions", with the catalog's plural rules.
    public func otherEditions(_ count: Int) -> String {
        String(localized: "\(count) other editions", locale: locale)
    }

    /// "from Deutsche Nationalbibliothek": where the card's book came from.
    public func fromSource(_ source: LookupSource) -> String {
        String(localized: "from \(source.displayName)", locale: locale)
    }

    /// "Already in your library", over the duplicate's title on the card.
    public func alreadyInLibraryHeading() -> String {
        String(localized: "Already in your library", locale: locale)
    }

    // MARK: Add Book's footer

    /// "Added in this round: 2", with the catalog's plural rules.
    public func addedInRound(_ count: Int) -> String {
        String(localized: "Added in this round: \(count)", locale: locale)
    }
}
