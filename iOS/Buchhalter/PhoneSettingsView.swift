import SwiftUI

// iOS-only: the Mac's Settings window as one sheet.

/// Book Lookup (the sources, their order and the Google Books key) and
/// iCloud, the Mac's two tabs, as sections of one scrolling sheet. The panes
/// are the shared ones; `section` is where it opens (iCloud from the sync line).
struct PhoneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var section: SettingsSection

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionTitle("Book Lookup")
                        BookLookupSettingsPane()
                        Divider().padding(.horizontal, 20)
                        sectionTitle("iCloud")
                            .id(SettingsSection.iCloud)
                        ICloudSettingsPane()
                    }
                }
                // Book Lookup is at the top already; iCloud is scrolled to (the sync line).
                .onAppear { if section == .iCloud { proxy.scrollTo(SettingsSection.iCloud, anchor: .top) } }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.top, 24)
    }
}
