import SwiftUI
import BuchhalterCore

/// A day, shown as a button that opens a calendar. Picking a day closes the
/// calendar. The system date field's calendar stays open after a pick and
/// cannot be closed from SwiftUI, so every date in the app goes through this.
struct DateField: View {
    @Environment(\.locale) private var locale
    @Environment(\.isEnabled) private var isEnabled
    /// Used as the accessibility label.
    var label: LocalizedStringKey
    @Binding var date: Date
    var range: PartialRangeFrom<Date> = Date.distantPast...
    /// The latest day that can be picked, if any.
    var through: Date?

    @State private var isOpen = false

    var body: some View {
        Button {
            isOpen = true
        } label: {
            HStack(spacing: 6) {
                Text(BookFormatting(locale: locale).day(date))
                    .monospacedDigit()
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(Text(label))
        .accessibilityValue(BookFormatting(locale: locale).day(date))
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            DatePicker(label, selection: Binding(
                get: { date },
                set: { picked in
                    date = Calendar.current.startOfDay(for: picked)
                    isOpen = false
                }
            ), in: range.lowerBound...max(range.lowerBound, through ?? .distantFuture), displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(12)
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { isOpen = false } }
    }
}
