import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (`UTExportedTypeDeclarations`), so a stray text
    /// drop is never mistaken for a book.
    nonisolated static let buchhalterBook = UTType(exportedAs: "local.buchhalter.book", conformingTo: .data)
}

/// What a dragged book carries: its id.
nonisolated struct BookDragItem: Codable, Transferable {
    var id: UUID

    nonisolated static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .buchhalterBook)
    }
}

/// An image dropped from Finder, Preview or a browser.
nonisolated struct DroppedImage: Transferable {
    let data: Data

    nonisolated static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { DroppedImage(data: $0) }
        FileRepresentation(importedContentType: .image) { received in
            DroppedImage(data: try Data(contentsOf: received.file))
        }
    }
}
