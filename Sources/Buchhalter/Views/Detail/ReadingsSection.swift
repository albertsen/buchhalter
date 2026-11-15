import SwiftUI
import BuchhalterCore

/// Every read-through of the book, newest first. A double click edits one.
struct ReadingsSection: View {
    @Environment(\.locale) private var locale
    var model: WindowModel
    var book: Book

    var body: some View {
        let readings = book.readingsNewestFirst
        if !readings.isEmpty {
            let formatting = BookFormatting(locale: locale)
            VStack(alignment: .leading, spacing: 8) {
                Text("Readings")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(readings.enumerated()), id: \.element.id) { index, reading in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(reading.status.displayName)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 110, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(formatting.readingSummary(reading))
                                    .font(.system(size: 13))
                                if let rating = reading.stars { StarRatingView(rating: rating) }
                                if let notes = reading.notes {
                                    Text(notes)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            model.sheet = .editReading(book: book.id, reading: reading.id)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Double-click to edit")
                        if index < readings.count - 1 { Divider() }
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.3)) }
            }
        }
    }
}
