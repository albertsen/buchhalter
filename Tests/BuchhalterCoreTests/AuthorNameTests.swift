import Testing
@testable import BuchhalterCore

struct AuthorNameTests {
    @Test func guessesSortNames() {
        #expect(AuthorName.guessSortName("Thomas Mann") == "Mann, Thomas")
        #expect(AuthorName.guessSortName("Johann Wolfgang von Goethe") == "Goethe, Johann Wolfgang von")
        #expect(AuthorName.guessSortName("Homer") == "Homer")
        #expect(AuthorName.guessSortName("Ludwig van Beethoven") == "Beethoven, Ludwig van")
        #expect(AuthorName.guessSortName("  Thomas   Mann ") == "Mann, Thomas")
        #expect(AuthorName.guessSortName("") == "")
    }

    @Test func matchKeyFoldsCaseAndAccents() {
        #expect(AuthorName.matchKey("Heinrich Böll") == AuthorName.matchKey("heinrich  boll"))
        #expect(AuthorName.matchKey("Thomas Mann") != AuthorName.matchKey("Heinrich Mann"))
    }

    @Test func normalizeCollapsesWhitespace() {
        #expect(AuthorName.normalize("  a \t b\n") == "a b")
    }
}
