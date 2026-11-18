import Foundation

/// Maps a MARC 21 record from the Deutsche Nationalbibliothek to a
/// `LookupRecord`. The field rules are the ones probed against real records;
/// see the book-lookup plan, Research and Decisions 14 and 15.
enum DNBRecordMapper {
    /// U+0098 and U+009C mark the part of a title that is ignored when sorting.
    private static let nonSortStart: Character = "\u{98}"
    private static let nonSortEnd: Character = "\u{9C}"

    /// Nil for a record that is not a printed book (audio, video, computer
    /// media, online resources) and for one without a title.
    static func record(from marc: MARCRecord) -> LookupRecord? {
        guard isPrint(marc),
              let title245 = marc.field("245"), let rawTitle = title245.first("a") else { return nil }
        let (title, matchKeys) = titles(from: rawTitle)
        guard !title.isEmpty else { return nil }
        let subtitle = title245.first("b").map { clean($0, removingNonSort: false) }.flatMap { $0.isEmpty ? nil : $0 }
        let identifier = marc.controlFields["001"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !identifier.isEmpty else { return nil }

        let language = languageCode(in: marc)
        let original = marc.field("041")?.first("h").flatMap(BibliographicLanguage.alpha2)
        let (isbn13s, display) = isbns(in: marc)

        return LookupRecord(
            id: "dnb:\(identifier)", source: .dnb, title: title, titleMatchKeys: matchKeys,
            subtitle: subtitle, authors: authors(in: marc), year: year(in: marc), pages: pages(in: marc),
            language: language, originalLanguage: original == language ? nil : original,
            publisher: publisher(in: marc), isbn13s: isbn13s, isbnDisplay: display,
            cover: isbn13s.first.map { .dnb(isbn13: $0) },
            synopsis: synopsis(in: marc)
        )
    }

    // MARK: Synopsis

    private static let dnbHosts = ["dnb.de", "d-nb.de", "d-nb.info"]

    /// The publisher's blurb the record links (856 with `$3` "Inhaltstext"),
    /// else the first summary (520). The blurb wins: a 520 can belong to
    /// another edition's language. Newer records link the blurb on
    /// services.dnb.de, older ones on deposit.dnb.de or d-nb.info; any DNB
    /// host counts, always over https (the sandbox allows no plain http).
    static func synopsis(in marc: MARCRecord) -> SynopsisReference? {
        for field in marc.fields("856") where field.first("3")?.trimmingCharacters(in: .whitespaces) == "Inhaltstext" {
            guard let raw = field.first("u"), var components = URLComponents(string: raw.trimmingCharacters(in: .whitespaces)),
                  let host = components.host?.lowercased(), dnbHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
            else { continue }
            components.scheme = "https"
            if let url = components.url { return .dnbBlurb(url) }
        }
        for field in marc.fields("520") {
            if let summary = field.first("a").flatMap(SynopsisText.cleanedSummary) { return .text(summary) }
        }
        return nil
    }

    // MARK: Carrier

    /// `mat=books` still returns audio carriers, and `007` is unreliable (a
    /// Polish audio CD has "tu"). `337$a`, `300$a` and, when present, `007`
    /// together decide. Records without 337 and 338 are kept.
    static func isPrint(_ marc: MARCRecord) -> Bool {
        let nonPrintMedia = ["audio", "video", "computer", "online"]
        if let media = marc.field("337")?.first("a")?.lowercased(),
           nonPrintMedia.contains(where: { media.contains($0) }) { return false }
        if let carrier = marc.field("338")?.first("a")?.lowercased(),
           ["online", "audio", "video", "computer"].contains(where: { carrier.contains($0) }) { return false }
        if let extent = marc.field("300")?.first("a"), words(in: extent).contains(where: carrierWords.contains) { return false }
        if let form = marc.controlFields["007"]?.trimmingCharacters(in: .whitespaces), !form.isEmpty,
           !form.hasPrefix("t") { return false }
        return true
    }

    /// Words in an extent statement that name something other than pages.
    private static let carrierWords: Set<String> = [
        "cd", "cds", "dvd", "mp3", "online-ressource", "online", "audiodisk", "hörbuch", "karte", "karten",
    ]

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }).map(String.init)
    }

    // MARK: Title

    /// The title with only the markers removed, and the folded forms to match
    /// against: with and without the non-sort part.
    private static func titles(from raw: String) -> (title: String, keys: [String]) {
        let withMarkers = clean(raw, removingNonSort: false)
        let withoutNonSort = clean(raw, removingNonSort: true)
        var keys: [String] = []
        for form in [withoutNonSort, withMarkers] {
            let key = TextFolding.fold(AuthorName.normalize(form))
            if !key.isEmpty, !keys.contains(key) { keys.append(key) }
        }
        return (withMarkers, keys)
    }

    /// Removes the non-sort markers (and the text between them when asked) and
    /// the ISBD punctuation that trails a subfield (" /", " :", " ;", " =").
    private static func clean(_ text: String, removingNonSort: Bool) -> String {
        var result = ""
        var skipping = false
        for character in text {
            if character == nonSortStart {
                skipping = removingNonSort
            } else if character == nonSortEnd {
                skipping = false
            } else if !skipping {
                result.append(character)
            }
        }
        var normalized = AuthorName.normalize(result)
        while let last = normalized.last, " /:;=,".contains(last) {
            normalized.removeLast()
        }
        return normalized
    }

    // MARK: Authors

    /// The 100 heading (any relator) and the 700 headings with `$4 = aut`.
    /// A 700 with a `$t` is a title entry, not a person.
    private static func authors(in marc: MARCRecord) -> [LookupAuthor] {
        var headings: [String] = []
        if let main = marc.field("100")?.first("a") { headings.append(main) }
        for field in marc.fields("700") where field.all("4").contains("aut") && field.first("t") == nil {
            if let heading = field.first("a") { headings.append(heading) }
        }
        var seen = Set<String>()
        var result: [LookupAuthor] = []
        for heading in headings {
            let author = LookupMatching.headingToName(heading)
            if !author.name.isEmpty, seen.insert(AuthorName.matchKey(author.name)).inserted { result.append(author) }
        }
        return result
    }

    // MARK: Publication

    /// 264 ind2 1 `$c`, then 264 ind2 4, then 260 `$c`, then 008 positions 7-10.
    private static func year(in marc: MARCRecord) -> Int? {
        let fields264 = marc.fields("264")
        let candidates = fields264.filter { $0.ind2 == "1" } + fields264.filter { $0.ind2 == "4" } + marc.fields("260")
        for field in candidates {
            if let text = field.first("c"), let value = LookupMatching.year(in: text) { return value }
        }
        if let control = marc.controlFields["008"], control.count >= 11 {
            let start = control.index(control.startIndex, offsetBy: 7)
            let slice = String(control[start..<control.index(start, offsetBy: 4)])
            if let value = Int(slice), (1000...2999).contains(value) { return value }
        }
        return nil
    }

    private static func publisher(in marc: MARCRecord) -> String? {
        let fields = marc.fields("264").filter { $0.ind2 == "1" } + marc.fields("260")
        for field in fields {
            guard let raw = field.first("b") else { continue }
            let cleaned = clean(raw, removingNonSort: false)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    // MARK: Extent

    /// The first Arabic integer of `300$a` that is not inside brackets. When
    /// its next word is a carrier or volume word ("1 CD", "2 Bände"), the
    /// extent is not a page count at all and the result is nil.
    static func pages(in marc: MARCRecord) -> Int? {
        guard let extent = marc.field("300")?.first("a") else { return nil }
        let volumeWords: Set<String> = [
            "bd", "bde", "band", "bände", "bd.", "vol", "vol.", "volumes", "cd", "dvd", "online-ressource", "karte", "karten",
        ]
        let characters = Array(extent)
        var index = 0
        var bracketDepth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "[" { bracketDepth += 1 }
            if character == "]" { bracketDepth = max(0, bracketDepth - 1) }
            guard character.isASCII, character.isNumber, bracketDepth == 0 else { index += 1; continue }
            var end = index
            while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
            let number = Int(String(characters[index..<end]))
            let rest = String(characters[end...]).trimmingCharacters(in: .whitespaces)
            let nextWord = rest.prefix { !$0.isWhitespace && $0 != "," && $0 != ";" && $0 != "(" }.lowercased()
            if volumeWords.contains(nextWord) || volumeWords.contains(nextWord.trimmingCharacters(in: CharacterSet(charactersIn: "."))) {
                return nil
            }
            if let number, (1...99_999).contains(number) { return number }
            return nil
        }
        return nil
    }

    // MARK: Language

    /// 041 `$a`, else 008 positions 35-37.
    private static func languageCode(in marc: MARCRecord) -> String? {
        if let code = marc.field("041")?.first("a"), let alpha2 = BibliographicLanguage.alpha2(code) { return alpha2 }
        if let control = marc.controlFields["008"], control.count >= 38 {
            let start = control.index(control.startIndex, offsetBy: 35)
            return BibliographicLanguage.alpha2(String(control[start..<control.index(start, offsetBy: 3)]))
        }
        return nil
    }

    // MARK: ISBN

    /// Every valid ISBN of the record as ISBN-13, the 13-digit `020$a` first,
    /// then the rest, then `024` ind1 3. The display form is `020$9` when it
    /// is the same number as the first, else the digits.
    private static func isbns(in marc: MARCRecord) -> (isbn13s: [String], display: String?) {
        struct Candidate { var isbn13: String; var hyphenated: String?; var was13: Bool }
        var candidates: [Candidate] = []
        for field in marc.fields("020") {
            guard let raw = field.first("a") else { continue }
            let token = String(raw.prefix { !$0.isWhitespace && $0 != "(" })
            guard case .valid(let isbn) = ISBN.parse(token) else { continue }
            var hyphenated: String?
            if let nine = field.first("9"), case .valid(let other) = ISBN.parse(nine), other == isbn { hyphenated = nine }
            candidates.append(Candidate(isbn13: isbn.isbn13, hyphenated: hyphenated, was13: ISBN.significantCount(token) == 13))
        }
        for field in marc.fields("024") where field.ind1 == "3" {
            if let raw = field.first("a"), case .valid(let isbn) = ISBN.parse(raw) {
                candidates.append(Candidate(isbn13: isbn.isbn13, hyphenated: nil, was13: true))
            }
        }
        let ordered = candidates.filter(\.was13) + candidates.filter { !$0.was13 }
        var seen = Set<String>()
        let unique = ordered.filter { seen.insert($0.isbn13).inserted }
        guard let first = unique.first else { return ([], nil) }
        return (unique.map(\.isbn13), first.hyphenated ?? first.isbn13)
    }
}
