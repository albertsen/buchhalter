import SwiftUI
import BuchhalterCore

// Mac-only: "Open Settings…" needs the macOS `openSettings` action.

/// Presents Find Cover's two alerts: "No cover found", which offers Open
/// Settings… when Google Books has no key or is off, and "Can't reach any
/// book source".
struct FindCoverAlertModifier: ViewModifier {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.locale) private var locale
    var model: WindowModel

    func body(content: Content) -> some View {
        content.alert(
            title, isPresented: Binding(get: { model.coverAlert != nil }, set: { if !$0 { model.coverAlert = nil } }),
            presenting: model.coverAlert
        ) { alert in
            if case .noCover(suggestsGoogleBooks: true) = alert {
                Button("Open Settings…") { openSettings() }
                    .keyboardShortcut(.defaultAction)
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            switch alert {
            case .noCover(let suggestsGoogleBooks):
                Text(verbatim: LookupMessages(locale: locale).noCoverMessage(suggestingGoogleBooks: suggestsGoogleBooks))
            case .noSourceReached:
                Text("Check the internet connection.")
            }
        }
    }

    private var title: LocalizedStringKey {
        switch model.coverAlert {
        case .noSourceReached: "Can't reach any book source"
        case .noCover, nil: "No cover found"
        }
    }
}
