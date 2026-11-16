import Foundation
import SwiftData
import Testing
@testable import BuchhalterCore

@MainActor
struct LegacyLibraryTests {
    /// A temporary folder that is removed again.
    private final class Scratch {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        func folder(_ name: String) throws -> URL {
            let folder = url.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// A real store with one book and a cover, so the external storage folder exists.
    private func makeLibrary(in folder: URL, books: Int = 1) throws {
        let container = try LibraryContainer.make(at: folder.appending(path: LibraryLocation.storeFileName))
        let library = Library(context: container.mainContext)
        for index in 0..<books {
            var draft = BookDraft()
            draft.title = "Book \(index)"
            draft.coverData = Data(repeating: UInt8(index + 1), count: 300_000)
            try library.addBook(draft)
        }
    }

    /// The listing once SwiftData has stopped touching the files of a store it
    /// just closed (the write-ahead log is checkpointed in the background).
    private func settledListing(_ folder: URL) async throws -> [String] {
        var current = try listing(folder)
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(50))
            let next = try listing(folder)
            if next == current { return next }
            current = next
        }
        return current
    }

    /// Names, sizes and modification dates of everything below `folder`.
    private func listing(_ folder: URL) throws -> [String] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        let enumerator = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys))
        var lines: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            lines.append("\(url.path.dropFirst(folder.path.count)) \(values.fileSize ?? -1) \(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return lines.sorted()
    }

    @Test func theCopyBringsStoreLogsAndCoversAndLeavesTheSourceAlone() async throws {
        let scratch = try Scratch()
        let legacy = try scratch.folder("legacy")
        try makeLibrary(in: legacy, books: 3)
        // A write-ahead log and shared memory, as a store that was not closed cleanly has.
        for suffix in ["-wal", "-shm"] {
            let url = legacy.appending(path: "\(LibraryLocation.storeFileName)\(suffix)")
            if !FileManager.default.fileExists(atPath: url.path) { try Data("x".utf8).write(to: url) }
        }
        let before = try await settledListing(legacy)
        let target = scratch.url.appending(path: "container", directoryHint: .isDirectory)

        try LegacyLibrary.copy(from: legacy, to: target)

        let names = try FileManager.default.contentsOfDirectory(atPath: target.path)
        #expect(Set(names) == Set(["library.store", "library.store-wal", "library.store-shm", ".library_SUPPORT"]))
        let after = try listing(legacy)
        #expect(after == before, "\(Set(after).symmetricDifference(Set(before)).sorted())")
        #expect(try listing(target.appending(path: ".library_SUPPORT")).count == listing(legacy.appending(path: ".library_SUPPORT")).count)
        // The copy opens as a library with its books.
        let container = try LibraryContainer.make(at: target.appending(path: LibraryLocation.storeFileName))
        #expect(Library(context: container.mainContext).fetchBooks().count == 3)
    }

    @Test func aFailedCopyLeavesNoStoreAndNoTemporaryFolder() throws {
        let scratch = try Scratch()
        let legacy = try scratch.folder("legacy")
        try makeLibrary(in: legacy)
        let external = legacy.appending(path: ".library_SUPPORT/_EXTERNAL_DATA")
        let cover = try #require(try FileManager.default.contentsOfDirectory(atPath: external.path).first)
        let coverURL = external.appending(path: cover)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: coverURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: coverURL.path) }
        let target = scratch.url.appending(path: "container", directoryHint: .isDirectory)

        #expect(throws: (any Error).self) { try LegacyLibrary.copy(from: legacy, to: target) }

        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    @Test func aMissingLegacyStoreThrows() throws {
        let scratch = try Scratch()
        #expect(throws: (any Error).self) {
            try LegacyLibrary.copy(from: scratch.url, to: scratch.url.appending(path: "target"))
        }
    }

    @Test func anEmptyTargetStoreIsReplaced() throws {
        let scratch = try Scratch()
        let legacy = try scratch.folder("legacy")
        let target = try scratch.folder("container")
        try makeLibrary(in: legacy, books: 2)
        try makeLibrary(in: target, books: 0)
        #expect(!LegacyLibrary.storeHasBooks(in: target))

        try LegacyLibrary.copy(from: legacy, to: target)

        #expect(LegacyLibrary.storeHasBooks(in: target))
        #expect(try !FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasPrefix(".copy-") })
    }

    // MARK: Rule

    @Test func theRuleCopiesIntoAMissingOrBooklessTargetOnce() throws {
        let scratch = try Scratch()
        let legacy = try scratch.folder("legacy")
        let target = scratch.url.appending(path: "container", directoryHint: .isDirectory)
        // No legacy store: nothing to copy.
        #expect(!LegacyLibrary.needsCopy(legacy: legacy, target: target, hasBooks: false, copyDate: nil))
        try makeLibrary(in: legacy)
        #expect(LegacyLibrary.needsCopy(legacy: legacy, target: target, hasBooks: false, copyDate: nil))
        // A target with books, or a copy made before, is never replaced.
        #expect(!LegacyLibrary.needsCopy(legacy: legacy, target: target, hasBooks: true, copyDate: nil))
        #expect(!LegacyLibrary.needsCopy(legacy: legacy, target: target, hasBooks: false, copyDate: .now))
        // Never from the folder to itself (an unsandboxed run, or $BUCHHALTER_HOME).
        #expect(!LegacyLibrary.needsCopy(legacy: legacy, target: legacy, hasBooks: false, copyDate: nil))
    }

    @Test func booksAreCountedWithoutOpeningTheStoreThroughSwiftData() throws {
        let scratch = try Scratch()
        #expect(!LegacyLibrary.storeHasBooks(in: scratch.url))
        let empty = try scratch.folder("empty")
        try makeLibrary(in: empty, books: 0)
        #expect(!LegacyLibrary.storeHasBooks(in: empty))
        let full = try scratch.folder("full")
        try makeLibrary(in: full, books: 1)
        #expect(LegacyLibrary.storeHasBooks(in: full))
    }

    // MARK: Preferences

    @Test func theNineKeysCarryOverAndNothingElse() {
        let plist: [String: Any] = [
            "lookupSources": "dnb:on", "googleBooksKeyState": "works", "selectedList": "read",
            "selectedBook": "A", "openBook": "", "sidebarWidth": 300, "listWidth": 820,
            "WindowFrame main": "19 0 1404 923", "NSWindow Frame main": "19 0 1404 923",
            "libraryListOrder": "read,reading,wantToRead,all", "scanCamera": "X",
            "NSSplitView Subview Frames main, SidebarNavigationSplitView": [],
        ]
        let carried = LegacyLibrary.defaultsToCarryOver(plist)
        #expect(Set(carried.keys) == Set(LegacyLibrary.carriedDefaultsKeys))
        #expect(carried.count == 9)
        #expect(carried["listWidth"] as? Int == 820)
    }

    @Test func thePreferencesFileIsReadWithoutUserDefaults() throws {
        let scratch = try Scratch()
        let preferences = try scratch.folder("Library/Preferences")
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["selectedList": "read"], format: .binary, options: 0)
        try data.write(to: preferences.appending(path: "local.buchhalter.plist"))
        #expect(LegacyLibrary.readPreferences(home: scratch.url)?["selectedList"] as? String == "read")
        #expect(LegacyLibrary.readPreferences(home: scratch.url.appending(path: "nowhere")) == nil)
    }
}
