import SwiftUI
import BuchhalterCore

// iOS-only: the card over the camera for one read ISBN.

/// What the card shows for each `ScanCard.Phase`: the sources being asked,
/// the book found with its editions, status and collections, or why there is
/// none. The buttons are the scanner's.
struct ScanCardView: View {
    @Environment(\.locale) private var locale
    @Bindable var card: ScanCardModel
    var collections: [Collection]
    var onAdd: () -> Void
    var onEdit: () -> Void
    var onSkip: () -> Void
    var onRetry: () -> Void
    var onEditions: () -> Void
    var onCollections: () -> Void

    private var messages: ScanMessages { ScanMessages(locale: locale) }
    private var query: LookupQuery { .isbn(card.card.isbn, display: card.card.isbn.hyphenated) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch card.card.phase {
            case .looking(let source):
                header {
                    Text(verbatim: messages.isbnRead(card.card.isbn)).font(.headline)
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(verbatim: LookupMessages(locale: locale).searching(query, source: source))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                buttons(primary: nil)
            case .found:
                found
            case .notFound:
                Text(verbatim: messages.isbnRead(card.card.isbn)).font(.headline)
                Text(verbatim: LookupMessages(locale: locale).noMatch(query))
                    .font(.subheadline)
                    .foregroundStyle(Theme.warningText)
                HStack(spacing: 10) {
                    Button(action: onSkip) { Text("Skip").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button(action: onEdit) { Text("Edit…").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
            case .unreachable:
                Text(verbatim: messages.isbnRead(card.card.isbn)).font(.headline)
                Text("Can't reach any book source")
                    .font(.subheadline)
                    .foregroundStyle(Theme.error)
                HStack(spacing: 10) {
                    Button(action: onEdit) { Text("Edit…").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button(action: onRetry) { Text("Try Again").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .controlSize(.large)
        .cardBackground()
    }

    // MARK: Found

    @ViewBuilder
    private var found: some View {
        header {
            Text(verbatim: card.draft.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
            if !card.draft.authors.isEmpty {
                Text(verbatim: card.draft.authors.map(\.name).joined(separator: ", "))
                    .font(.subheadline)
            }
            if let line = detailLine {
                Text(verbatim: line).font(.footnote).foregroundStyle(.secondary)
            }
            if let record = card.card.record {
                Text(verbatim: messages.fromSource(record.source))
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            if card.card.otherEditionCount > 0 {
                Button(action: onEditions) {
                    HStack(spacing: 3) {
                        Text(verbatim: messages.otherEditions(card.card.otherEditionCount))
                        Image(systemName: "chevron.right").imageScale(.small)
                    }
                }
                .font(.footnote)
                .buttonStyle(.borderless)
            }
        }
        StatusSegments(status: $card.draft.status)
        Button(action: onCollections) {
            HStack {
                Text("Collections").foregroundStyle(.secondary)
                Text(verbatim: collectionNames).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(collections.isEmpty)
        buttons(primary: onAdd)
    }

    private func buttons(primary: (() -> Void)?) -> some View {
        HStack(spacing: 10) {
            Button(action: onEdit) { Text("Edit…").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
                .layoutPriority(1)
            Button(action: primary ?? {}) {
                Text("Add and Scan Next").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
            }
            .buttonStyle(.borderedProminent)
            .layoutPriority(2)
            .disabled(primary == nil || !card.canAdd)
        }
    }

    /// The cover and the lines next to it.
    private func header<Lines: View>(@ViewBuilder lines: () -> Lines) -> some View {
        HStack(alignment: .top, spacing: 14) {
            cover
            VStack(alignment: .leading, spacing: 3, content: lines)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let data = card.draft.coverData, let image = ThumbnailCache.image(from: data, longestSide: 96) {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 64, height: 96)
        }
    }

    /// "Fischer · 1989 · 759 pages".
    private var detailLine: String? {
        let formatting = BookFormatting(locale: locale)
        var parts: [String] = []
        if !card.draft.publisher.isEmpty { parts.append(card.draft.publisher) }
        if !card.draft.yearText.isEmpty { parts.append(card.draft.yearText) }
        if let pages = Int(card.draft.pagesText) { parts.append(formatting.pageCount(pages)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var collectionNames: String {
        let names = collections.filter { card.draft.collectionIDs.contains($0.id) }.map(\.name)
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }
}
