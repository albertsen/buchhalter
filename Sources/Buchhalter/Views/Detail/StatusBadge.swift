import SwiftUI
import BuchhalterCore

/// "Reading since 3 Oct 2026", "Finished 2 Mar 2019", "Abandoned", "Want to Read".
struct StatusBadge: View {
    @Environment(\.locale) private var locale
    var reading: Reading

    var body: some View {
        Text(BookFormatting(locale: locale).badge(reading))
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.tint, in: Capsule())
            .foregroundStyle(Theme.tintText)
    }
}
