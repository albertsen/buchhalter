import SwiftUI
import BuchhalterCore

/// The one-time sheet after the first launch of the synced version: the
/// library goes to iCloud, and the old copy stays on this Mac. It never comes
/// back: closing it, however it is closed, sets `syncNoticeShown`.
struct SyncNoticeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncActions) private var actions
    @Environment(\.locale) private var locale
    @AppStorage(SyncDefaults.syncNoticeShown) private var shown = false
    var bookCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "icloud")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Your Library Now Syncs with iCloud")
                    .font(Theme.serif(20))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Buchhalter keeps your library in your private iCloud. It is safe if this Mac is lost, and the iPhone and iPad app shows the same books.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                bullet(SyncMessages(locale: locale).noticeCount(bookCount))
                bullet(String(localized: "A copy of the library from before the first sync is kept on this Mac.", locale: locale))
            }
            Text("The sync status is in Settings → iCloud.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Show Copy in Finder") { actions.showLegacyFolder?() }
                Button("OK") { close() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .sheetWidth(520)
        .onDisappear { shown = true }
        // Esc closes it too, like OK.
        .background {
            Button("OK") { close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: "•").foregroundStyle(.secondary)
            Text(verbatim: text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func close() {
        shown = true
        dismiss()
    }
}
