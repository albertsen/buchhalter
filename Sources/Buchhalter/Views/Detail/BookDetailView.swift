import SwiftUI
import BuchhalterCore

/// The selected book: large cover, title, status, buttons, collections, readings.
struct BookDetailView: View {
    @Environment(\.library) private var library
    @Environment(\.locale) private var locale
    var model: WindowModel
    var book: Book
    var collections: [Collection]

    var body: some View {
        let formatting = BookFormatting(locale: locale)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 24) {
                    CoverView(book: book, size: CGSize(width: 120, height: 180))
                        .dropDestination(for: DroppedImage.self) { items, _ in
                            guard let data = items.first?.data else { return false }
                            setCover(data)
                            return true
                        }
                        .contextMenu {
                            if book.coverImage != nil {
                                Button("Remove Cover Image") {
                                    model.attempt { try library?.setCover(nil, for: book) }
                                }
                            }
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(Theme.serif(28))
                            .textSelection(.enabled)
                        if let subtitle = book.subtitle {
                            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
                        }
                        let authors = book.orderedAuthors.map(\.name).joined(separator: ", ")
                        if !authors.isEmpty { Text(authors).font(.system(size: 15)) }
                        VStack(alignment: .leading, spacing: 2) {
                            let meta = formatting.metaLine(book)
                            if !meta.isEmpty { Text(meta) }
                            Text(formatting.added(book))
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        if let reading = book.currentReading {
                            StatusBadge(reading: reading).padding(.top, 8)
                        }
                        buttons.padding(.top, 6)
                    }
                }
                CollectionChips(model: model, book: book, collections: collections)
                ReadingsSection(model: model, book: book)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            switch book.status {
            case .reading:
                Button("Finish Reading…") { model.sheet = .finish(book.id) }
                    .buttonStyle(.borderedProminent)
                Button("Abandon") { model.sheet = .abandon(book.id) }
                    .secondaryAction()
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            case .finished, .abandoned:
                Button("Read Again") { model.attempt { try library?.readAgain(book) } }
                    .secondaryAction()
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            case .wantToRead, nil:
                Button("Edit") { model.sheet = .editBook(book.id) }
                    .secondaryAction()
            }
        }
        .controlSize(.regular)
    }

    private func setCover(_ data: Data) {
        Task {
            do {
                let normalized = try await CoverImage.normalize(data)
                model.attempt { try library?.setCover(normalized, for: book) }
            } catch {
                model.errorMessage = String(localized: "This image can't be used.")
            }
        }
    }
}

private extension View {
    /// The window's accent tint colours a system bordered button's label, so
    /// dark mode showed dark green text on a dark button. Secondary actions use
    /// their own style with the normal label colour; only the prominent action
    /// is green.
    func secondaryAction() -> some View {
        buttonStyle(SecondaryButtonStyle())
    }
}

/// A neutral bordered button: label in the primary colour, a quiet fill and
/// a hairline border that work in light and dark mode.
private struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.18))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(isEnabled ? 1 : 0.4)
    }
}
