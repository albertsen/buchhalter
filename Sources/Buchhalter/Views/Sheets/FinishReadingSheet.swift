import SwiftUI
import BuchhalterCore

/// Finish Reading: only the finish date is required.
struct FinishReadingSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    var model: WindowModel
    var book: Book
    @State private var finishedAt = Calendar.current.startOfDay(for: .now)
    @State private var rating: Int?
    @State private var notes = ""

    var body: some View {
        let formatting = BookFormatting(locale: locale)
        let started = book.currentReading?.startedAt
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Finish Reading").font(.system(size: 17, weight: .semibold))
                Text(titleLine).foregroundStyle(.secondary)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .firstTextBaseline) {
                    label("Started")
                    Text(started.map(formatting.day) ?? "–")
                }
                GridRow(alignment: .firstTextBaseline) {
                    label("Finished on")
                    DatePicker("Finished", selection: $finishedAt, in: (started ?? .distantPast)..., displayedComponents: .date)
                        .labelsHidden()
                }
                GridRow(alignment: .firstTextBaseline) {
                    label("Rating")
                    StarRatingControl(rating: $rating)
                }
                GridRow(alignment: .firstTextBaseline) {
                    label("Notes")
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(height: 110)
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)) }
                        .accessibilityLabel("Notes")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Finish") {
                    model.attempt {
                        try library?.finishReading(book, on: finishedAt, rating: rating, notes: notes)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var titleLine: String {
        let authors = book.orderedAuthors.map(\.name).joined(separator: ", ")
        return authors.isEmpty ? book.title : "\(book.title) · \(authors)"
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).foregroundStyle(.secondary).fixedSize().frame(minWidth: 70, alignment: .trailing).gridColumnAlignment(.trailing)
    }
}
