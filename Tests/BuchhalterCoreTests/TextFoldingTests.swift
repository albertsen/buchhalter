import Foundation
import Testing
@testable import BuchhalterCore

struct TextFoldingTests {
    @Test func umlautSortsWithItsBaseLetter() {
        let names = ["Zola", "Ärger", "Adams", "Böll"].sorted { TextFolding.compare($0, $1) == .orderedAscending }
        #expect(names == ["Adams", "Ärger", "Böll", "Zola"])
    }

    @Test func foldsCaseAndDiacritics() {
        #expect(TextFolding.fold("Böll") == "boll")
        #expect(TextFolding.compare("boll", "BÖLL") == .orderedSame)
    }

    @Test func numbersSortNumerically() {
        #expect(TextFolding.compare("Band 2", "Band 10") == .orderedAscending)
    }

    @Test func titleKeyDropsOneLeadingArticle() {
        #expect(TextFolding.titleSortKey("Der Zauberberg") == "Zauberberg")
        #expect(TextFolding.titleSortKey("The Hours") == "Hours")
        #expect(TextFolding.titleSortKey("a tale of two cities") == "tale of two cities")
        #expect(TextFolding.titleSortKey("A") == "A")
        #expect(TextFolding.titleSortKey("Die") == "Die")
        #expect(TextFolding.titleSortKey("Buddenbrooks") == "Buddenbrooks")
    }
}
