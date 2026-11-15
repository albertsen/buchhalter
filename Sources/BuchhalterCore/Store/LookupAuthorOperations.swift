import Foundation

@MainActor
extension Library {
    /// Turns a record's authors into draft authors. An author already in the
    /// library keeps its stored name and sort name. A new one gets the
    /// heading's sort name, or the usual guess. Duplicates are dropped.
    /// Nothing is inserted; the draft is saved only with the book.
    public func lookupAuthors(_ authors: [LookupAuthor]) -> [AuthorDraft] {
        let known = existingAuthors()
        var seen = Set<String>()
        var result: [AuthorDraft] = []
        for author in authors {
            let name = AuthorName.normalize(author.name)
            let key = AuthorName.matchKey(name)
            guard !name.isEmpty, seen.insert(key).inserted else { continue }
            if let existing = known[key] {
                result.append(AuthorDraft(name: existing.name, sortName: existing.sortName, isExisting: true))
            } else {
                let sortName = author.sortName.map(AuthorName.normalize).flatMap { $0.isEmpty ? nil : $0 }
                result.append(AuthorDraft(name: name, sortName: sortName ?? AuthorName.guessSortName(name)))
            }
        }
        return result
    }
}
