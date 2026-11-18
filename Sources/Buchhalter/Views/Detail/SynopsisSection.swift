import SwiftUI
#if os(iOS)
import UIKit
#endif
import BuchhalterCore

/// The book's synopsis in the detail: cut after four lines with More, the
/// whole text after More, and the source it came from. On the Mac a click on
/// the text edits it in place, like the header's fields: Return or clicking
/// elsewhere saves, ⌥Return or ⇧Return starts a new line, Escape cancels.
/// The field is as tall as its text. A book without a synopsis shows no
/// section; Find Synopsis or Edit Book's Synopsis tab adds one.
struct SynopsisSection: View {
    @Environment(\.library) private var library
    @Environment(\.locale) private var locale
    var model: WindowModel
    var book: Book

    @State private var isExpanded = false
    @State private var isEditing = false
    @State private var editText = ""
    /// The book being edited, so a change of selection saves to the right one.
    @State private var editingBook: Book?
    @State private var isHovered = false
    @FocusState private var editorFocused: Bool

    private static let collapsedLines = 4

    var body: some View {
        if book.synopsis != nil || isEditing {
            VStack(alignment: .leading, spacing: 8) {
                Text("Synopsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                if isEditing {
                    editor
                } else if let synopsis = book.synopsis {
                    text(synopsis)
                    footer
                }
            }
            .frame(maxWidth: 620, alignment: .leading)
            .onChange(of: book.id) {
                finish()
                isExpanded = false
            }
        }
    }

    // MARK: Editing (Mac)

    /// A `TextEditor` scrolls inside a fixed frame; the hidden copy of the
    /// text underneath gives it the height of the whole text, plus one line
    /// so a new line never scrolls.
    private var editor: some View {
        ZStack(alignment: .topLeading) {
            Text(verbatim: editText + "\n ")
                .font(textFont)
                .lineSpacing(3)
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
            TextEditor(text: $editText)
                .font(textFont)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($editorFocused)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
        .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.accent, lineWidth: 1.5) }
        .onKeyPress(.escape) {
            isEditing = false
            editingBook = nil
            return .handled
        }
        // Return saves, like the header's fields; with ⌥ or ⇧ it is a new line.
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.option, .shift]) else { return .ignored }
            finish()
            return .handled
        }
        .onChange(of: editorFocused) { _, now in
            if !now { finish() }
        }
        .onAppear { editorFocused = true }
        .accessibilityLabel("Synopsis")
    }

    private func begin() {
        #if os(macOS)
        editText = book.synopsis ?? ""
        editingBook = book
        isEditing = true
        #endif
    }

    /// An unchanged text keeps its source; an edited one is the user's.
    private func finish() {
        guard isEditing, let target = editingBook else { return }
        isEditing = false
        editingBook = nil
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (target.synopsis ?? "") else { return }
        model.attempt {
            try library?.updateDetails(of: target) { draft in
                draft.synopsis = trimmed
                draft.synopsisSource = nil
            }
        }
    }

    private var textFont: Font {
        #if os(iOS)
        Theme.serif(16, weight: .regular)
        #else
        Theme.serif(14, weight: .regular)
        #endif
    }

    private func text(_ synopsis: String) -> some View {
        Text(verbatim: synopsis)
            .font(textFont)
            .lineSpacing(3)
            .lineLimit(isExpanded ? nil : Self.collapsedLines)
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(macOS)
            .padding(.horizontal, 3)
            .background { RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(isHovered ? 0.06 : 0)) }
            .padding(.horizontal, -3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { begin() }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { begin() }
            #else
            .textSelection(.enabled)
            #endif
            // A hidden copy without the limit tells whether the limit cuts anything.
            .background(alignment: .topLeading) {
                Text(verbatim: synopsis)
                    .font(textFont)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                        fullHeight = full
                    }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown in
                shownHeight = shown
            }
            #if os(iOS)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = synopsis }
                Button("Edit…", systemImage: "pencil") { model.sheet = .editSynopsis(book.id) }
                Button("Remove Synopsis", systemImage: "trash", role: .destructive) {
                    model.attempt { try library?.setSynopsis(nil, source: nil, for: book) }
                }
            }
            #endif
    }

    @State private var fullHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0

    /// The collapsed text is shorter than the whole by more than rounding.
    private var canExpand: Bool { isExpanded || fullHeight > shownHeight + 1 }

    @ViewBuilder
    private var footer: some View {
        let source = book.synopsisSource
        if canExpand || source != nil {
            HStack(spacing: 14) {
                if canExpand {
                    Button(isExpanded ? "Less" : "More") { isExpanded.toggle() }
                        .linkButtonStyle()
                        .font(.system(size: 12))
                }
                if let source {
                    Text(verbatim: LookupMessages(locale: locale).synopsisFrom(source))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
