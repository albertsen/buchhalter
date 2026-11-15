import Testing
@testable import BuchhalterCore

struct BibliographicLanguageTests {
    @Test func allTwentyBibliographicCodesMapToTwoLetters() {
        let expected = [
            "alb": "sq", "arm": "hy", "baq": "eu", "bur": "my", "chi": "zh", "cze": "cs", "dut": "nl",
            "fre": "fr", "geo": "ka", "ger": "de", "gre": "el", "ice": "is", "mac": "mk", "mao": "mi",
            "may": "ms", "per": "fa", "rum": "ro", "slo": "sk", "tib": "bo", "wel": "cy",
        ]
        #expect(expected.count == 20)
        for (code, alpha2) in expected {
            #expect(BibliographicLanguage.alpha2(code) == alpha2, "\(code)")
        }
    }

    @Test func terminologyCodesAndCaseWork() {
        #expect(BibliographicLanguage.alpha2("jpn") == "ja")
        #expect(BibliographicLanguage.alpha2("eng") == "en")
        #expect(BibliographicLanguage.alpha2("GER") == "de")
        #expect(BibliographicLanguage.alpha2("de") == "de")
    }

    @Test func unknownCodesGiveNil() {
        #expect(BibliographicLanguage.alpha2("xxx") == nil)
        #expect(BibliographicLanguage.alpha2("") == nil)
        #expect(BibliographicLanguage.alpha2("german") == nil)
    }
}
