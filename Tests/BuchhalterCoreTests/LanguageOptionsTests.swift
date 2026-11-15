import Foundation
import Testing
@testable import BuchhalterCore

struct LanguageOptionsTests {
    @Test func offeredCodesAreTheTwoLetterOnesWithAName() {
        let en = Locale(identifier: "en")
        for code in ["de", "en", "ja", "ka", "zh"] { #expect(LanguageOptions.isOffered(code, locale: en), "\(code)") }
        for code in ["deu", "zz", "", "d", "mul"] { #expect(!LanguageOptions.isOffered(code, locale: en), "\(code)") }
    }

    @Test func offeredMatchesWhatThePopupLists() {
        let en = Locale(identifier: "en")
        let listed = LanguageOptions.codes(used: [], locale: en).others
        #expect(!listed.isEmpty)
        #expect(listed.allSatisfy { LanguageOptions.isOffered($0, locale: en) })
    }
}
