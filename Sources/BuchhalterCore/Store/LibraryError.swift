import Foundation

public enum LibraryError: LocalizedError {
    case emptyTitle
    case invalidISBN
    case invalidRating
    case emptyCollectionName
    case duplicateCollectionName
    case finishBeforeStart
    case noOpenReading
    case readingAlreadyOpen
    case saveFailed(any Error)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: String(localized: "A book needs a title.")
        case .invalidISBN: String(localized: "This ISBN is not valid. Check the last digit.")
        case .invalidRating: String(localized: "A rating is 1 to 5 stars.")
        case .emptyCollectionName: String(localized: "A collection needs a name.")
        case .duplicateCollectionName: String(localized: "A collection with this name already exists.")
        case .finishBeforeStart: String(localized: "The finish date can't be before the start date.")
        case .noOpenReading: String(localized: "This book is not being read.")
        case .readingAlreadyOpen: String(localized: "This book already has an open reading.")
        case .saveFailed(let error):
            String(localized: "The library could not be saved: \(error.localizedDescription)")
        }
    }
}
