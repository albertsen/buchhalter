import Foundation
import Testing
@testable import BuchhalterCore

struct MARCParsingTests {
    private func parse(_ name: String) throws -> MARCParseResult {
        try MARCXMLParser.parse(fixture(name))
    }

    private func marc(tag: String, ind2: String = " ", _ subfields: [(String, String)]) -> MARCDataField {
        MARCDataField(tag: tag, ind1: " ", ind2: ind2, subfields: subfields.map { MARCSubfield(code: $0.0, value: $0.1) })
    }

    /// A minimal printed-book record with the fields a test changes.
    private func record(_ fields: [MARCDataField], control: [String: String] = [:]) -> MARCRecord {
        var controlFields = ["001": "1", "007": "tu"]
        controlFields.merge(control) { _, new in new }
        return MARCRecord(controlFields: controlFields, dataFields: [marc(tag: "245", [("a", "Titel")])] + fields)
    }

    // MARK: Parser

    @Test func buddenbrooksFixtureParses() throws {
        let result = try parse("dnb-buddenbrooks-mann.xml")
        #expect(result.numberOfRecords == 477)
        #expect(result.records.count == 20)
        #expect(!result.hasDiagnostic)
    }

    @Test func carrierFilterDropsThePolishAudioCD() throws {
        let result = try parse("dnb-buddenbrooks-mann.xml")
        let mapped = result.records.compactMap(DNBRecordMapper.record(from:))
        #expect(mapped.count == 19)
        // The CD's 007 is "tu", so only 337 and 300 give it away.
        let cd = try #require(result.records.first { $0.field("245")?.first("a") == "Buddenbrookowie" })
        #expect(cd.controlFields["007"] == "tu")
        #expect(DNBRecordMapper.record(from: cd) == nil)
        #expect(!mapped.contains { $0.title == "Buddenbrookowie" })
    }

    @Test func nonSortMarkersAreRemovedAndBothFormsMatch() throws {
        let mapped = try parse("dnb-buddenbrooks-mann.xml").records.compactMap(DNBRecordMapper.record(from:))
        let oxford = try #require(mapped.first { $0.title.hasSuffix("Buddenbrooks") && $0.title.hasPrefix("The") })
        #expect(oxford.title == "The Buddenbrooks")
        #expect(oxford.titleMatchKeys.contains("buddenbrooks"))
        #expect(oxford.titleMatchKeys.contains("the buddenbrooks"))
    }

    @Test func piercingRecordMapsEveryField() throws {
        let result = try parse("dnb-isbn-piercing.xml")
        #expect(result.numberOfRecords == 1)
        let marc = try #require(result.records.first)
        let record = try #require(DNBRecordMapper.record(from: marc))
        #expect(record.id == "dnb:991442512")
        #expect(record.source == .dnb)
        #expect(record.title == "Piercing")
        #expect(record.subtitle == "Roman")
        #expect(record.authors == [LookupAuthor(name: "Ryū Murakami", sortName: "Murakami, Ryū")])
        #expect(record.publisher == "Liebeskind")
        #expect(record.year == 2009)
        #expect(record.pages == 173)
        #expect(record.language == "de")
        #expect(record.originalLanguage == "ja")
        #expect(record.isbn13s == ["9783935890595"])
        #expect(record.isbnDisplay == "978-3-935890-59-5")
        #expect(record.cover == .dnb(isbn13: "9783935890595"))
    }

    @Test func stonerRecordsStripMarkersAndExtraPageText() throws {
        let mapped = try parse("dnb-stoner-williams.xml").records.compactMap(DNBRecordMapper.record(from:))
        #expect(mapped.contains { $0.pages == 380 })
        #expect(mapped.contains { $0.title.hasPrefix("Der Mann, der") })
        #expect(mapped.allSatisfy { !$0.title.contains("\u{98}") && !$0.title.contains("\u{9C}") })
    }

    @Test func noMatchFixtureHasNoRecords() throws {
        let result = try parse("dnb-no-match.xml")
        #expect(result.records.isEmpty)
        #expect(result.numberOfRecords == 0)
    }

    @Test func malformedXMLThrows() {
        #expect(throws: (any Error).self) { try MARCXMLParser.parse(Data("<a><b></a>".utf8)) }
    }

    @Test func diagnosticsAreFlagged() throws {
        let xml = """
        <searchRetrieveResponse xmlns="http://www.loc.gov/zing/srw/"><version>1.1</version><numberOfRecords>0</numberOfRecords>\
        <diagnostics><diagnostic xmlns="http://www.loc.gov/zing/srw/diagnostic/"><uri>info:srw/diagnostic/1/10</uri><message>Query syntax error</message></diagnostic></diagnostics>\
        </searchRetrieveResponse>
        """
        #expect(try MARCXMLParser.parse(Data(xml.utf8)).hasDiagnostic)
    }

    // MARK: Years

    @Test func yearForms() {
        for (text, year) in [("[2026]", 2026), ("©2026", 2026), ("copyright 2026", 2026), ("© 2026", 2026), ("2025.05", 2025), ("2009", 2009)] {
            let mapped = DNBRecordMapper.record(from: record([marc(tag: "264", ind2: "1", [("c", text)])]))
            #expect(mapped?.year == year, "\(text)")
        }
    }

    @Test func yearFallsBackToCopyrightThen260Then008() {
        let copyright = DNBRecordMapper.record(from: record([marc(tag: "264", ind2: "4", [("c", "©2001")])]))
        #expect(copyright?.year == 2001)
        let old = DNBRecordMapper.record(from: record([marc(tag: "260", [("c", "1999")])]))
        #expect(old?.year == 1999)
        let control = DNBRecordMapper.record(from: record([], control: ["008": "081126s2009    gw ||||| |||| 00||||ger  "]))
        #expect(control?.year == 2009)
        let preferred = DNBRecordMapper.record(from: record(
            [marc(tag: "264", ind2: "4", [("c", "©2001")]), marc(tag: "264", ind2: "1", [("c", "2010")])]
        ))
        #expect(preferred?.year == 2010)
    }

    // MARK: Pages

    @Test func pageForms() {
        for (text, pages) in [("666 pages", 666), ("717 mian", 717), ("173 S.", 173), ("781 Seiten", 781), ("380 Seiten, 5 ungezählte Seiten", 380)] {
            #expect(DNBRecordMapper.pages(in: record([marc(tag: "300", [("a", text)])])) == pages, "\(text)")
        }
    }

    @Test func carrierAndVolumeCountsAreNotPages() {
        for text in ["1 CD (22 godz. 42 min)", "2 Bände", "3 Bde.", "1 Online-Ressource", "[8] Bl."] {
            #expect(DNBRecordMapper.pages(in: record([marc(tag: "300", [("a", text)])])) == nil, "\(text)")
        }
    }

    // MARK: Headings and languages

    @Test func headingsBecomeNames() {
        let mann = LookupAuthor(name: "Thomas Mann", sortName: "Mann, Thomas")
        #expect(LookupMatching.headingToName("Mann, Thomas,, 1875-1955") == mann)
        #expect(LookupMatching.headingToName("Mann, Thomas, (1875-1955)") == mann)
        #expect(LookupMatching.headingToName("Mann, Thomas") == mann)
        #expect(LookupMatching.headingToName("Man en") == LookupAuthor(name: "Man en"))
        #expect(LookupMatching.headingToName("John Williams") == LookupAuthor(name: "John Williams"))
        #expect(LookupMatching.headingToName("Murakami, Ryū") == LookupAuthor(name: "Ryū Murakami", sortName: "Murakami, Ryū"))
    }

    @Test func languagesUseTheBibliographicTable() {
        let georgian = DNBRecordMapper.record(from: record([marc(tag: "041", [("a", "geo")])]))
        #expect(georgian?.language == "ka")
        let chinese = DNBRecordMapper.record(from: record([marc(tag: "041", [("a", "chi")])]))
        #expect(chinese?.language == "zh")
        let russian = DNBRecordMapper.record(from: record([marc(tag: "041", [("a", "rus"), ("h", "ger")])]))
        #expect(russian?.language == "ru")
        #expect(russian?.originalLanguage == "de")
        let same = DNBRecordMapper.record(from: record([marc(tag: "041", [("a", "ger"), ("h", "ger")])]))
        #expect(same?.originalLanguage == nil)
        let fallback = DNBRecordMapper.record(from: record([], control: ["008": "081126s2009    gw ||||| |||| 00||||fre  "]))
        #expect(fallback?.language == "fr")
    }

    // MARK: Other rules

    @Test func isbnPrefersThirteenDigitsAndHyphenatedDisplay() {
        let mapped = DNBRecordMapper.record(from: record([
            marc(tag: "020", [("a", "315011537X")]),
            marc(tag: "020", [("a", "9783150115374"), ("9", "978-3-15-011537-4")]),
        ]))
        #expect(mapped?.isbn13s == ["9783150115374"])
        #expect(mapped?.isbnDisplay == "978-3-15-011537-4")
    }

    @Test func isbnWithoutHyphenatedFormShowsDigits() {
        let mapped = DNBRecordMapper.record(from: record([marc(tag: "020", [("a", "315011537X (Pp.)")])]))
        #expect(mapped?.isbn13s == ["9783150115374"])
        #expect(mapped?.isbnDisplay == "9783150115374")
    }

    @Test func publisherTrimsPunctuation() {
        let mapped = DNBRecordMapper.record(from: record([marc(tag: "264", ind2: "1", [("b", "Reclam ,")])]))
        #expect(mapped?.publisher == "Reclam")
    }

    @Test func authorsComeFromTheMainHeadingAndAuthorRelators() {
        let mapped = DNBRecordMapper.record(from: record([
            marc(tag: "100", [("a", "Mann, Thomas,, 1875-1955"), ("4", "aut")]),
            marc(tag: "700", [("a", "Translator, Some"), ("4", "trl")]),
            marc(tag: "700", [("a", "Mann, Erika"), ("4", "aut")]),
            marc(tag: "700", [("a", "Mann, Thomas"), ("4", "aut")]),
        ]))
        #expect(mapped?.authors.map(\.name) == ["Thomas Mann", "Erika Mann"])
    }

    @Test func recordsWithoutTitleOrPrintCarrierAreDropped() {
        let noTitle = MARCRecord(controlFields: ["001": "1"], dataFields: [])
        #expect(DNBRecordMapper.record(from: noTitle) == nil)
        let online = record([marc(tag: "337", [("a", "Computermedien")])])
        #expect(DNBRecordMapper.record(from: online) == nil)
        let notPrint007 = record([], control: ["007": "cr"])
        #expect(DNBRecordMapper.record(from: notPrint007) == nil)
        let noCarrierFields = record([])
        #expect(DNBRecordMapper.record(from: noCarrierFields) != nil)
    }
}
