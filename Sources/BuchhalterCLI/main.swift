import AppKit
import BuchhalterCore
import BuchhalterKeychain
import Foundation
import SwiftData

// `buchhalter-cli`: maintenance commands on the library. Mac-only, English
// only (a tool for the developer, not part of the app's interface). It works on
// the same store as the app (`$BUCHHALTER_HOME` overrides the folder) and
// refuses to run while the app is open, so two processes never write at once.

let usage = """
    usage: buchhalter-cli <command> [options]

    commands:
      find-covers   Find Cover for every book without a cover, with the sources
                    and order from the app's Settings.
          --limit N        only the first N books without a cover (oldest first)
          --report FILE    write a tab-separated report: result, source,
                           search (isbn or title+author), title, author, ISBN
          --dry-run        search, but store nothing
      help          show this text

    The library is ~/Library/Application Support/Buchhalter/ unless
    $BUCHHALTER_HOME names another folder. Quit Buchhalter first.
    """

/// The app's bundle id and with it its UserDefaults domain. Changes with the
/// final bundle id (architecture.md, Phases).
let appBundleID = "local.buchhalter"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("buchhalter-cli: \(message)\n".utf8))
    exit(1)
}

// MARK: Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { print(usage); exit(0) }
arguments.removeFirst()

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name) else { return nil }
    guard arguments.indices.contains(index + 1) else { fail("\(name) needs a value") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

func flag(_ name: String) -> Bool {
    guard let index = arguments.firstIndex(of: name) else { return false }
    arguments.remove(at: index)
    return true
}

switch command {
case "help", "--help", "-h":
    print(usage)
case "find-covers":
    var limit: Int?
    if let text = option("--limit") {
        guard let value = Int(text), value > 0 else { fail("--limit needs a positive number") }
        limit = value
    }
    let report = option("--report").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    let dryRun = flag("--dry-run")
    guard arguments.isEmpty else { fail("unknown option \(arguments[0])\n\n\(usage)") }
    try await findCovers(limit: limit, report: report, dryRun: dryRun)
default:
    fail("unknown command \(command)\n\n\(usage)")
}

// MARK: find-covers

func findCovers(limit: Int?, report: URL?, dryRun: Bool) async throws {
    let url = try LibraryLocation.storeURL()
    // The app always opens the default library; a tool run on another
    // folder ($BUCHHALTER_HOME) cannot collide with it.
    let isAppLibrary = url == (try? LibraryLocation.storeURL(environment: [:]))
    if isAppLibrary, !NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID).isEmpty {
        fail("Buchhalter is open. Quit it first, so only one process writes to the library.")
    }

    // The sources and order from Settings; Google Books only with a saved key.
    let keys = KeychainSecretStore()
    let list = LookupSourceList(raw: UserDefaults(suiteName: appBundleID)?.string(forKey: "lookupSources") ?? "")
    let sources = list.active(hasGoogleKey: await keys.exists())
    guard !sources.isEmpty else { fail("every source is off in Settings") }
    let lookup = BookLookup(services: sources.map { $0.makeService(keys: keys) })

    let container = try LibraryContainer.make(at: url)
    let context = container.mainContext
    var books = try MissingCovers.books(in: context)
    if let limit { books = Array(books.prefix(limit)) }
    print("library: \(url.path)")
    print("sources: \(sources.map(\.displayName).joined(separator: ", "))")
    print("books without a cover: \(books.count)\(dryRun ? " (dry run, nothing is stored)" : "")")

    var lines = ["result\tsource\tsearch\ttitle\tauthor\tisbn"]
    var counts: [String: Int] = [:]
    let started = Date.now

    for (index, book) in books.enumerated() {
        let outcome = try await MissingCovers.search(for: book, using: lookup, pause: .milliseconds(300))
        let (result, source, search): (String, String, String)
        switch outcome {
        case .found(let data, let from, let byISBN):
            if !dryRun { book.coverImage = data }
            (result, source, search) = ("found", from.rawValue, byISBN ? "isbn" : "title+author")
        case .notFound: (result, source, search) = ("none", "", "")
        case .unreachable: (result, source, search) = ("error", "", "")
        case .nothingToSearch: (result, source, search) = ("skipped", "", "")
        }
        counts[result, default: 0] += 1
        let author = book.orderedAuthors.first?.name ?? ""
        lines.append([result, source, search, book.title, author, book.isbnText ?? ""].joined(separator: "\t"))

        let done = index + 1
        if done % 10 == 0 || done == books.count {
            if !dryRun { try context.save() }
            if let report { try (lines.joined(separator: "\n") + "\n").write(to: report, atomically: true, encoding: .utf8) }
            let minutes = Int(Date.now.timeIntervalSince(started) / 60)
            print("\(done)/\(books.count): found \(counts["found", default: 0]), none \(counts["none", default: 0]), "
                + "errors \(counts["error", default: 0]), skipped \(counts["skipped", default: 0]) · \(minutes) min")
        }
    }
    if let report { print("report: \(report.path)") }
}
