import SwiftUI

/// "Get a Google Books Key": the steps to a free key, over the Settings
/// window. The step names match the labels in Google's console. Open Google
/// Cloud Console opens the browser and leaves the sheet open; Done, Return and
/// Esc close it.
struct GoogleBooksKeyHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let steps: [LocalizedStringKey] = [
        "Sign in to the Google Cloud Console with your Google account.",
        "Create a project, for example \u{201C}Buchhalter\u{201D}.",
        "Turn on the Books API for the project.",
        "Create an API key under Credentials.",
        "Restrict the key to the Books API.",
        "Copy the key and paste it into Buchhalter's Settings.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Get a Google Books Key")
                .font(.system(size: 15, weight: .semibold))
            Text("The key is free. You need a Google account.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(verbatim: "\(index + 1).")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(step)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            HStack(spacing: 8) {
                Button("Open Google Cloud Console") {
                    if let url = URL(string: "https://console.cloud.google.com/") { openURL(url) }
                }
                Spacer()
                // Esc closes the sheet too.
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 480)
    }
}
