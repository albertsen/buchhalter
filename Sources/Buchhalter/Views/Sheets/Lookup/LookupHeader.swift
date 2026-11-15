import SwiftUI
import BuchhalterCore

/// The sheet's title row and the strip under it: the Complete button (or
/// "Looking up…" with Stop), and one line that is, in this order, the status
/// of a running lookup, the amber no-match hint, the red unreachable hint,
/// the green banner after filling, or the grey explanation.
struct LookupHeader: View {
    @Environment(\.locale) private var locale
    var title: LocalizedStringKey
    var lookup: LookupModel
    /// False until the sheet has a title and an author, or a valid ISBN.
    var canComplete: Bool
    var complete: () -> Void
    var stop: () -> Void
    var undo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                controls
            }
            strip
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if lookup.isRunning {
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Looking up…")
                }
            }
            .buttonStyle(CompleteButtonStyle())
            .disabled(true)
            Button("Stop", action: stop)
                .accessibilityLabel("Stop Lookup")
        } else {
            Button(action: complete) {
                Label("Complete", systemImage: "magnifyingglass")
            }
            .buttonStyle(CompleteButtonStyle())
            .disabled(!canComplete)
            // The tooltip says what is missing. It works on a disabled button.
            .help(canComplete ? "" : String(localized: "Enter a title and author, or an ISBN"))
        }
    }

    // MARK: Strip

    @ViewBuilder
    private var strip: some View {
        let messages = LookupMessages(locale: locale)
        switch lookup.phase {
        case .running(let query, let source):
            Text(verbatim: messages.searching(query, source: source))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        case .noMatch(let query):
            hint(messages.noMatch(query), fill: Theme.warningFill, text: Theme.warningText)
        case .unreachable(_, let source):
            hint(messages.unreachable(source), fill: Theme.errorFill, text: Theme.errorText, action: ("Try Again", complete))
        case .idle:
            if let result = lookup.result {
                hint(messages.banner(result), fill: Theme.tint, text: Theme.tintText, action: ("Undo", undo))
            } else {
                Text("Type a title and author, or an ISBN. Complete looks up the rest in the Deutsche Nationalbibliothek, including the cover.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func hint(
        _ message: String, fill: Color, text: Color, action: (LocalizedStringKey, () -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: action.1) { Text(action.0).underline() }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(text)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(fill, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }
}

/// The outlined Complete button from the design: a 1 pt accent border,
/// semibold text in the dark accent, 28 pt high.
private struct CompleteButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(.background, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isEnabled ? Theme.accent : Color.secondary.opacity(0.4), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }

    private var foreground: Color {
        guard isEnabled else { return .secondary }
        return colorScheme == .dark ? .white : Theme.tintText
    }
}
