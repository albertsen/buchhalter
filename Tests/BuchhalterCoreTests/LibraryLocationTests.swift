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
