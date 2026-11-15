import Foundation

/// A checked ISBN. Pure and `Sendable`.
public struct ISBN: Equatable, Sendable {
    /// The 13 digits, converted from ISBN-10 when needed.
    public let isbn13: String

    /// The one way the app writes an ISBN: the ISBN-13 with its hyphens in the
    /// places the International ISBN Agency assigns, "978-3-15-011537-4".
    public var hyphenated: String { ISBNHyphenation.shared.hyphenate(isbn13) }

    /// The hyphenated form of a valid ISBN, or the text unchanged.
    public static func formatted(_ text: String) -> String {
        if case .valid(let isbn) = parse(text) { return isbn.hyphenated }
        return text
    }

    public enum Check: Equatable, Sendable {
        case empty
        /// Fewer than 10 significant characters, or between 11 and 12.
        case incomplete
        case valid(ISBN)
        case invalid
    }

    /// Strips spaces and hyphens, accepts ISBN-10 (X as last character, either
    /// case) and ISBN-13 (978/979), and checks the checksum.
    public static func parse(_ text: String) -> Check {
        let chars = text.filter { !$0.isWhitespace && $0 != "-" }
        if chars.isEmpty { return .empty }
        switch chars.count {
        case 10:
            guard isValidISBN10(chars) else { return .invalid }
            return .valid(ISBN(isbn13: convert(chars)))
        case 13:
            guard isValidISBN13(chars) else { return .invalid }
            return .valid(ISBN(isbn13: String(chars)))
        case 0..<10, 11, 12:
            // Letters or other characters in a short input are still "not yet".
            return .incomplete
        default:
            return .invalid
        }
    }

    /// The number of significant characters (without spaces and hyphens).
    public static func significantCount(_ text: String) -> Int {
        text.filter { !$0.isWhitespace && $0 != "-" }.count
    }

    static func isValidISBN10(_ s: String) -> Bool {
        let chars = Array(s.uppercased())
        guard chars.count == 10 else { return false }
        var sum = 0
        for (i, c) in chars.enumerated() {
            let value: Int
            if c == "X" && i == 9 {
                value = 10
            } else if let d = c.wholeNumberValue, c.isASCII {
                value = d
            } else {
                return false
            }
            sum += value * (10 - i)
        }
        return sum % 11 == 0
    }

    static func isValidISBN13(_ s: String) -> Bool {
        let digits = s.compactMap { $0.isASCII ? $0.wholeNumberValue : nil }
        guard digits.count == 13, s.count == 13 else { return false }
        guard digits[0] == 9, digits[1] == 7, digits[2] == 8 || digits[2] == 9 else { return false }
        var sum = 0
        for (i, d) in digits.enumerated() { sum += d * (i % 2 == 0 ? 1 : 3) }
        return sum % 10 == 0
    }

    static func convert(_ isbn10: String) -> String {
        let body = "978" + isbn10.prefix(9)
        let digits = body.compactMap(\.wholeNumberValue)
        var sum = 0
        for (i, d) in digits.enumerated() { sum += d * (i % 2 == 0 ? 1 : 3) }
        let check = (10 - sum % 10) % 10
        return body + String(check)
    }
}
