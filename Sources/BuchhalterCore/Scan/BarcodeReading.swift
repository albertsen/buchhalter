import Foundation

/// What a scanned EAN-13 payload means for the library. Pure, so the rules
/// are tested without a camera.
public enum BarcodeReading {
    public enum Reading: Equatable, Sendable {
        /// A valid ISBN-13: 978 or 979 with a correct check digit.
        case isbn(ISBN)
        /// A valid EAN-13 that is not an ISBN (a price, a retail code). The
        /// display form is the way EAN codes are printed: "4 006381 333931".
        case notISBN(display: String)
        /// Not 13 digits, or a wrong check digit: a misread, or another kind
        /// of barcode. Never shown to the user.
        case ignored
    }

    /// Only 13 digits count. ISBN-10 strings are not accepted here, unlike
    /// `ISBN.parse`: the barcode on a book is always the ISBN-13.
    public static func classify(_ payload: String) -> Reading {
        let digits = payload.compactMap { $0.isASCII ? $0.wholeNumberValue : nil }
        guard payload.count == 13, digits.count == 13, hasValidCheckDigit(digits) else { return .ignored }
        if digits[0] == 9, digits[1] == 7, digits[2] == 8 || digits[2] == 9,
           case .valid(let isbn) = ISBN.parse(payload) {
            return .isbn(isbn)
        }
        return .notISBN(display: display(payload))
    }

    /// "4 006381 333931": the first digit, then two groups of six.
    static func display(_ digits: String) -> String {
        let first = digits.prefix(1)
        let middle = digits.dropFirst().prefix(6)
        let last = digits.dropFirst(7)
        return "\(first) \(middle) \(last)"
    }

    private static func hasValidCheckDigit(_ digits: [Int]) -> Bool {
        var sum = 0
        for (index, digit) in digits.enumerated() { sum += digit * (index % 2 == 0 ? 1 : 3) }
        return sum % 10 == 0
    }
}
