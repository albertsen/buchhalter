import SwiftUI
import BuchhalterCore

/// "Choose an edition": the books that matched, newest first, over Add Book
/// or Edit Book. Return, Use This Edition and a double-click use the selected
/// row; Cancel and Esc change nothing.
struct EditionPickerSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.bookLookup) private var bookLookup
    @Environment(\.colorScheme) private var colorScheme
    var list: EditionList
    var query: LookupQuery
    var use: (LookupRecord) -> Void
    var cancel: () -> Void

    @State private var selection: LookupRecord.ID?
    /// Small covers by record id, loaded as rows appear and kept while the sheet is open.
    @State private var thumbnails: [LookupRecord.ID: Data] = [:]

    var body: some View {
        let messages = LookupMessages(locale: locale)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose an edition")
                        .font(.system(size: 15, weight: .semibold))
                    Text(verbatim: messages.editionsHeadline(count: list.records.count, query: query))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if list.isTruncated {
                        Text(verbatim: messages.truncatedNote())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Google asks for its graphic next to its results.
                if list.source == .googleBooks { PoweredByGoogleMark() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 10)

            List(selection: $selection) {
                ForEach(list.records) { record in
                    row(record)
                        .tag(record.id)
                }
            }
            .contextMenu(forSelectionType: LookupRecord.ID.self) { _ in
            } primaryAction: { ids in
                if let record = list.records.first(where: { ids.contains($0.id) }) { use(record) }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)) }
            .padding(.horizontal, 12)
            .accessibilityLabel("Matches")

            HStack(spacing: 8) {
                Text("Double-click a row to use it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Use This Edition", action: useSelected)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedRecord == nil)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .sheetWidth(560)
        .onAppear { selection = selection ?? list.records.first?.id }
    }

    private var selectedRecord: LookupRecord? {
        list.records.first { $0.id == selection }
    }

    private func useSelected() {
        if let record = selectedRecord { use(record) }
    }

    // MARK: Row

    private func row(_ record: LookupRecord) -> some View {
        let formatting = BookFormatting(locale: locale)
        let isSelected = selection == record.id
        let secondary: AnyShapeStyle = isSelected ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary)
        return HStack(alignment: .top, spacing: 12) {
            cover(record)
                .frame(width: 36, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(Theme.serif(14))
                    .lineLimit(2)
                let byline = formatting.editionByline(record)
                if !byline.isEmpty {
                    Text(byline).font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
                }
                let details = formatting.editionDetails(record)
                if !details.isEmpty {
                    Text(details).font(.system(size: 12)).foregroundStyle(secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // Google asks for a prominent link to the book's page on every result.
            if let page = record.webPage {
                Link(destination: page) { Text(verbatim: "Google Books").underline() }
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(linkColor))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .task(id: record.id) {
            guard thumbnails[record.id] == nil, record.cover != nil else { return }
            if let data = await bookLookup.thumbnail(for: record) { thumbnails[record.id] = data }
        }
    }

    /// The deep green accent is unreadable on a dark list.
    private var linkColor: Color { colorScheme == .dark ? .primary : Theme.accent }

    @ViewBuilder
    private func cover(_ record: LookupRecord) -> some View {
        if let data = thumbnails[record.id], let image = ThumbnailCache.image(from: data, longestSide: 54) {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            GeneratedCoverView(
                id: Self.stableID(record.id), title: record.title,
                author: record.authors.map(\.name).joined(separator: ", "), size: CGSize(width: 36, height: 54)
            )
        }
    }

    /// A generated cover needs a UUID for its colour; a record has a string
    /// id. FNV-1a over the bytes keeps the colour stable between runs.
    private static func stableID(_ text: String) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        var bytes: [UInt8] = []
        for round in 0..<2 {
            for byte in text.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x100000001b3
            }
            hash = (hash ^ UInt64(round)) &* 0x100000001b3
            withUnsafeBytes(of: hash.bigEndian) { bytes.append(contentsOf: $0) }
        }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
