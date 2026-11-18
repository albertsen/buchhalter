import SwiftUI
import BuchhalterCore

/// The two parts of Add and Edit Book. The Mac shows them as tabs; iOS shows
/// the synopsis on a page of its own behind a row.
enum EditorTab: Hashable {
    case details, synopsis
}

/// The synopsis of the draft: a plain text area, where it came from, Remove
/// Synopsis, and the lookup's offer when a source has a different text. The
/// Mac's Synopsis tab and the iOS page are this view.
struct SynopsisEditor: View {
    @Environment(\.locale) private var locale
    @Binding var draft: BookDraft
    var lookup: LookupModel

    @State private var showsOffered = false

    private var messages: LookupMessages { LookupMessages(locale: locale) }

    /// Typing clears the source: an edited text is the user's.
    private var text: Binding<String> {
        Binding(
            get: { draft.synopsis },
            set: { newValue in
                guard newValue != draft.synopsis else { return }
                draft.synopsis = newValue
                draft.synopsisSource = nil
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            offer
            TextEditor(text: text)
                .font(editorFont)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3))
                    if lookup.result?.isHighlighted(.synopsis, in: draft) == true {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.filledBorder, lineWidth: 1)
                    }
                }
                .accessibilityLabel("Synopsis")
            HStack(spacing: 12) {
                if let source = draft.synopsisSource, !draft.synopsis.isEmpty {
                    Text(verbatim: messages.synopsisFrom(source))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                #if os(macOS)
                Button("Remove Synopsis") { remove() }
                    .controlSize(.small)
                    .disabled(draft.synopsis.isEmpty)
                #endif
            }
        }
        #if os(iOS)
        .padding(16)
        .navigationTitle("Synopsis")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Remove Synopsis", systemImage: "trash", role: .destructive) { remove() }
                        .disabled(draft.synopsis.isEmpty)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        #endif
    }

    private var editorFont: Font {
        #if os(iOS)
        Theme.serif(17, weight: .regular)
        #else
        Theme.serif(14, weight: .regular)
        #endif
    }

    private func remove() {
        draft.synopsis = ""
        draft.synopsisSource = nil
    }

    /// "Google Books has a different synopsis · Show · Use", and the source's
    /// text under it while Show is on.
    @ViewBuilder
    private var offer: some View {
        if let result = lookup.result, result.showsOffer(.synopsis, in: draft),
           let source = result.offeredSynopsisSource {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(verbatim: messages.differentSynopsis(source))
                    Text(verbatim: "·")
                    Button(showsOffered ? "Hide" : "Show") { showsOffered.toggle() }
                        .linkButtonStyle()
                    Text(verbatim: "·")
                    Button("Use") {
                        lookup.use(.synopsis, draft: &draft)
                        showsOffered = false
                    }
                    .linkButtonStyle()
                    .accessibilityLabel("Use Found Synopsis")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                if showsOffered {
                    ScrollView {
                        Text(verbatim: result.offerValue(.synopsis, formatting: BookFormatting(locale: locale)))
                            .font(editorFont)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 140)
                    .background(Theme.filledFill, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}

/// The Mac's Details and Synopsis tabs, drawn like `StatusSegments` so the
/// Synopsis tab can carry the green dot after Complete filled or offered it.
struct EditorTabs: View {
    @Binding var tab: EditorTab
    var marksSynopsis: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment(.details) { Text("Details") }
            segment(.synopsis) {
                HStack(spacing: 5) {
                    Text("Synopsis")
                    if marksSynopsis {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            .accessibilityLabel("Filled by Complete")
                    }
                }
            }
        }
        .padding(2)
        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
        .fixedSize()
        .accessibilityElement(children: .contain)
    }

    private func segment<Label: View>(_ value: EditorTab, @ViewBuilder label: () -> Label) -> some View {
        let isSelected = tab == value
        return Button {
            tab = value
        } label: {
            label()
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .frame(height: 22)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5).fill(.background)
                            .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
