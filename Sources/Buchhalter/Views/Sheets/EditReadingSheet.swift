import SwiftUI
import BuchhalterCore

/// Edit one reading: dates, rating and notes, or delete it.
struct EditReadingSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    var model: WindowModel
    var reading: Reading
    @State private var startedAt: Date?
    @State private var endedAt: Date?
    @State private var rating: Double?
    @State private var notes: String

    init(model: WindowModel, reading: Reading) {
        self.model = model
        self.reading = reading
        _startedAt = State(initialValue: reading.startedAt)
        _endedAt = State(initialValue: reading.endedAt)
        _rating = State(initialValue: reading.stars)
        _notes = State(initialValue: reading.notes ?? "")
    }

    private var status: ReadingStatus { reading.status }
    private var dateOrderIsWrong: Bool {
        if let startedAt, let endedAt { return endedAt < startedAt }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Reading").font(.system(size: 17, weight: .semibold))
                Text(status.displayName).foregroundStyle(.secondary)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .firstTextBaseline) {
                    label("Started")
                    OptionalDatePicker(date: $startedAt)
                }
                if status == .finished || status == .abandoned {
                    GridRow(alignment: .firstTextBaseline) {
                        label(status == .finished ? "Finished on" : "Abandoned on")
                        OptionalDatePicker(date: $endedAt)
                    }
                    if dateOrderIsWrong {
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Text("The finish date can't be before the start date.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.error)
                        }
                    }
                }
                if status == .finished {
                    GridRow(alignment: .firstTextBaseline) {
                        label("Rating")
                        StarRatingControl(rating: $rating)
                    }
                }
                GridRow(alignment: .firstTextBaseline) {
                    label("Notes")
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(height: 90)
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)) }
                        .accessibilityLabel("Notes")
                }
            }
            HStack {
                Button("Delete Reading", role: .destructive) {
                    model.attempt {
                        try library?.deleteReading(reading)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.attempt {
                        try library?.updateReading(
                            reading, startedAt: startedAt, endedAt: status == .reading || status == .wantToRead ? nil : endedAt,
                            rating: status == .finished ? rating : reading.stars, notes: notes
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(dateOrderIsWrong)
            }
        }
        .padding(24)
        .sheetWidth(460, half: true)
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).foregroundStyle(.secondary).fixedSize().frame(minWidth: 70, alignment: .trailing).gridColumnAlignment(.trailing)
    }
}
