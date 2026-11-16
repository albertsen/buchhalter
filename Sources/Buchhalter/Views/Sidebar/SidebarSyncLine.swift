import SwiftUI
import BuchhalterCore

/// The line at the bottom of the sidebar: the first upload or download, or a
/// problem. Everyday syncs never show it, so it does not flicker. Clicking it
/// opens Settings on the iCloud tab.
struct SidebarSyncLine: View {
    var line: SyncSidebarLine
    /// The problem is a red one (sync stopped), not an amber one (sign in, storage full).
    var isError = false
    @Environment(\.syncActions) private var actions
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            actions.openSyncSettings()
        } label: {
            HStack(spacing: 6) {
                icon
                Text(verbatim: SyncMessages(locale: locale).sidebarLine(line))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the iCloud settings"))
    }

    @ViewBuilder
    private var icon: some View {
        switch line {
        case .uploading, .downloading:
            ProgressView().controlSize(.mini).frame(width: 14, height: 14)
        case .problem:
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 12))
                .foregroundStyle(isError ? Theme.error : Color.orange)
                .accessibilityHidden(true)
        }
    }
}
