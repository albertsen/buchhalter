import Foundation

/// Name handling for authors: whitespace, matching and the sort-name guess.
public enum AuthorName {
    /// Trims and collapses runs of whitespace.
    public static func normalize(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The folded form two names are compared by.
    public static func matchKey(_ name: String) -> String {
        TextFolding.fold(normalize(name))
    }

    private static let particles: Set<String> = [
        "von", "van", "de", "der", "den", "du", "da", "di", "del", "della",
        "des", "la", "le", "zu", "zum", "zur", "vom", "ten", "ter",
    ]

    /// "Thomas Mann" gives "Mann, Thomas". Lowercase particles directly before
    /// the surname move behind the given names. Capitalized particles ("Le Guin")
    /// are not recognized; the user corrects those.
    public static func guessSortName(_ name: String) -> String {
        let words = normalize(name).split(separator: " ").map(String.init)
        guard words.count > 1, let surname = words.last else { return words.first ?? "" }
        var givenCount = words.count - 1
        while givenCount > 1, particles.contains(words[givenCount - 1]) {
            givenCount -= 1
        }
        let given = words[0..<givenCount]
        let particle = words[givenCount..<(words.count - 1)]
        let tail = (Array(given) + Array(particle)).joined(separator: " ")
        return "\(surname), \(tail)"
    }
}
