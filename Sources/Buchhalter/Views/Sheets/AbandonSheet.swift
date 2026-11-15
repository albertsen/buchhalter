import SwiftUI
import BuchhalterCore

/// Abandon: an optional date and an optional note. No confirmation dialog.
struct AbandonSheet: View {
    @Environment(\.library) private var library
    @Environment(\.dismiss) private var dismiss
    var model: WindowModel
    var book: Book
    @State private var hasDate = true
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("abandonSheet.title").font(.system(size: 17, weight: .semibold))
                Text(book.title).foregroundStyle(.secondary)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow(alignment: .firstTextBaseline) {
                    Toggle("Date", isOn: $hasDate)
                        .fixedSize().frame(minWidth: 70, alignment: .trailing).gridColumnAlignment(.trailing)
                    DateField(label: "Date", date: $date, range: (book.currentReading?.startedAt ?? .distantPast)...)
                        .disabled(!hasDate)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Note").foregroundStyle(.secondary).fixedSize().frame(minWidth: 70, alignment: .trailing).gridColumnAlignment(.trailing)
                    TextEditor(text: $notes)
                        .font(.body)
                        .frame(height: 80)
                        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)) }
                        .accessibilityLabel("Note")
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("abandonSheet.confirm") {
                    model.attempt {
                        try library?.abandonReading(book, on: hasDate ? date : nil, notes: notes)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
