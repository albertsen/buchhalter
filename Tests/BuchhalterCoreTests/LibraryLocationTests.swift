import Foundation
import Testing
@testable import BuchhalterCore

struct LibraryLocationTests {
    @Test func homeVariableReplacesTheFolder() {
        let folder = LibraryLocation.folder(environment: ["BUCHHALTER_HOME": "/tmp/scratch-lib"])
        #expect(folder.path == "/tmp/scratch-lib")
    }

    @Test func emptyOrMissingVariableUsesApplicationSupport() {
        for environment in [[:], ["BUCHHALTER_HOME": ""]] as [[String: String]] {
            let folder = LibraryLocation.folder(environment: environment)
            #expect(folder.path.hasSuffix("Library/Application Support/Buchhalter"))
        }
    }

    @Test func storeURLCreatesTheFolderOnlyUnderTheGivenHome() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try LibraryLocation.storeURL(environment: ["BUCHHALTER_HOME": folder.path])
        #expect(url.lastPathComponent == "library.store")
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }
}

struct LegacyFolderTests {
    @Test func theLegacyFolderIsUnderTheGivenHome() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        #expect(LibraryLocation.legacyFolder(home: home).path == "/Users/someone/Library/Application Support/Buchhalter")
    }

    @Test func theRealHomeIsNotEmpty() {
        #expect(LibraryLocation.realHome().path.hasPrefix("/"))
    }
}

struct StoreBytesTests {
    @Test func countsTheStoreItsLogsAndTheCovers() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let external = folder.appending(path: ".library_SUPPORT/_EXTERNAL_DATA", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 1000).write(to: folder.appending(path: "library.store"))
        try Data(count: 200).write(to: folder.appending(path: "library.store-wal"))
        try Data(count: 3000).write(to: external.appending(path: "cover"))
        try Data(count: 5).write(to: folder.appending(path: "run.log"))
        #expect(LibraryLocation.storeBytes(in: folder) == 4200)
        #expect(LibraryLocation.storeBytes(in: folder.appending(path: "missing")) == 0)
    }
}
