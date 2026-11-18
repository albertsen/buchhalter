import SwiftUI
import BuchhalterCore

// Mac-only: "Open Settings…" needs the macOS `openSettings` action.

/// Presents Find Cover's and Find Synopsis's alerts: "No cover found", which offers Open
/// Settings… when Google Books has no key or is off, and "Can't reach any
/// book source".
struct FindCoverAlertModifier: ViewModifier {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.locale) private var locale
    var model: WindowModel

    func body(content: Content) -> some View {
        content.alert(
            title, isPresented: Binding(get: { model.findAlert != nil }, set: { if !$0 { model.findAlert = nil } }),
            presenting: model.findAlert
        ) { alert in
            if alert.suggestsGoogleBooks {
                Button("Open Settings…") { openSettings() }
                    .keyboardShortcut(.defaultAction)
            }
            Button("OK", role: .cancel) {}
        } message: { alert in
            switch alert {
            case .noCover(let suggestsGoogleBooks):
                Text(verbatim: LookupMessages(locale: locale).noCoverMessage(suggestingGoogleBooks: suggestsGoogleBooks))
            case .noSynopsis(let suggestsGoogleBooks):
                Text(verbatim: LookupMessages(locale: locale).noSynopsisMessage(suggestingGoogleBooks: suggestsGoogleBooks))
            case .noSourceReached:
                Text("Check the internet connection.")
            }
        }
    }

    private var title: LocalizedStringKey {
        switch model.findAlert {
        case .noSourceReached: "Can't reach any book source"
        case .noSynopsis: "No synopsis found"
        case .noCover, nil: "No cover found"
        }
    }
}
