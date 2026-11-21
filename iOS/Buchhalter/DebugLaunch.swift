#if DEBUG
import SwiftUI
import SwiftData
import BuchhalterCore

// iOS-only, Debug builds only: launch arguments that let an agent look at a
// screen in the simulator without tapping. They act only in the simulator or
// on a scratch library (`BUCHHALTER_HOME` set), never on the real one. Release builds, which is
// what `make ios` installs, have none of this.
//
//   -debugSeed YES          fills an empty scratch library with sample books
//   -debugScreen <screen>   list | book | addBook | settings | authors | author

enum DebugLaunch {
    static let bookID = UUID(uuidString: "00000000-0000-0000-0000-00000000B00C") ?? UUID()

    /// A scratch store, or the simulator's own, which is never the real library.
    private static var isScratch: Bool {
        BuchhalterPhoneApp.isSimulator || !(ProcessInfo.processInfo.environment["BUCHHALTER_HOME"] ?? "").isEmpty
    }

    static var screen: String? {
        isScratch ? UserDefaults.standard.string(forKey: "debugScreen") : nil
    }

    /// Whether the iPhone starts with a list pushed over the Library screen.
    static var showsList: Bool { ["list", "book", "authors", "author"].contains(screen) }

    /// A handful of books in every status, with German titles that test the widths.
    @MainActor
    static func seedIfRequested(_ container: ModelContainer) {
        guard isScratch, UserDefaults.standard.bool(forKey: "debugSeed") else { return }
        let library = Library(context: container.mainContext)
        guard ((try? container.mainContext.fetchCount(FetchDescriptor<Book>())) ?? 0) == 0 else { return }
        let samples: [(String, String, DraftStatus?, Int)] = [
            ("Piercing", "Ryu Murakami", .reading, 2009),
            ("Buddenbrooks", "Thomas Mann", .read, 1901),
            ("Der Zauberberg", "Thomas Mann", .wantToRead, 1924),
            ("Effi Briest", "Theodor Fontane", .wantToRead, 1896),
            ("Stoner", "John Williams", .read, 1965),
        ]
        for (title, author, status, year) in samples {
            var draft = BookDraft()
            draft.title = title
            draft.subtitle = title == "Piercing" ? "Roman" : ""
            draft.authors = [library.suggestedAuthor(for: author)]
            draft.status = status
            draft.yearText = String(year)
            draft.pagesText = "173"
            draft.language = "de"
            if status == .reading { draft.startedAt = Calendar.current.startOfDay(for: .now) }
            if let book = try? library.addBook(draft), title == "Piercing" { book.id = bookID }
        }
        for name in ["Gelesen 2025", "Gelesen 2026", "Klassiker"] {
            _ = try? library.createCollection(named: name)
        }
        try? container.mainContext.save()
        let authors = screen == "authors" || screen == "author"
        UserDefaults.standard.set((authors ? LibraryListID.authors : .reading).rawValue, forKey: "selectedList")
        if screen == "author", let mann = AuthorIndex.authors(in: (try? container.mainContext.fetch(FetchDescriptor<Book>())) ?? []).first(where: { $0.name == "Thomas Mann" }) {
            UserDefaults.standard.set(mann.id.uuidString, forKey: "openAuthor")
        }
        UserDefaults.standard.set(screen == "book" ? bookID.uuidString : "", forKey: "selectedBook")
    }

    /// Opens the requested sheet once the window is up.
    @MainActor
    static func openScreen(model: WindowModel, phone: PhoneUI) {
        switch screen {
        case "addBook": model.sheet = .addBook
        case "settings": phone.settings = .bookLookup
        default: break
        }
    }
}
#endif
