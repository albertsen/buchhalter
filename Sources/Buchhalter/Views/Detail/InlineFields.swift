import SwiftUI
import BuchhalterCore

// MARK: Text

/// A piece of the detail that turns into a text field when clicked. Return or
/// clicking elsewhere saves, Escape cancels. `commit` returns an error
/// message for a value the library refuses: Return then keeps the field open
/// with a red outline, clicking elsewhere drops the value.
struct InlineTextField: View {
    /// The stored value, as it is edited.
    var value: String
    /// What shows when not editing; the value when nil.
    var display: String?
    var placeholder: LocalizedStringKey
    var font: Font
    /// An empty field shows its placeholder only while the pointer is over
    /// the header, so the detail stays quiet.
    var revealsEmpty: Bool
    /// The title takes the full width; the meta line's pieces size to their text.
    var fillsWidth = false
    var commit: (String) -> String?

    @State private var isEditing = false
    @State private var text = ""
    @State private var error: String?
    @State private var isHovered = false
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            TextField(text: $text, prompt: Text(placeholder)) { Text(placeholder) }
                .textFieldStyle(.plain)
                .font(font)
                .focused($focused)
                .padding(.horizontal, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(error == nil ? Theme.accent : Theme.error, lineWidth: 1.5)
                }
                .help(error ?? "")
                .frame(minWidth: 60, maxWidth: fillsWidth ? .infinity : 220, alignment: .leading)
                .fixedSize(horizontal: !fillsWidth, vertical: false)
                .onSubmit { finish(keepOnError: true) }
                .onKeyPress(.escape) {
                    cancel()
                    return .handled
                }
                .onChange(of: focused) { _, now in
                    if !now { finish(keepOnError: false) }
                }
                .onChange(of: text) { error = nil }
                .onAppear { focused = true }
        } else if !value.isEmpty || revealsEmpty {
            (value.isEmpty ? Text(placeholder) : Text(verbatim: display ?? value))
                .font(font)
                .foregroundStyle(value.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .padding(.horizontal, 3)
                .background {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                }
                .padding(.horizontal, -3)
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .onTapGesture { begin() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(placeholder))
                .accessibilityValue(Text(verbatim: display ?? value))
                .accessibilityAction { begin() }
        }
    }

    private func begin() {
        text = value
        error = nil
        isEditing = true
    }

    private func cancel() {
        error = nil
        isEditing = false
    }

    private func finish(keepOnError: Bool) {
        guard isEditing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != value else {
            isEditing = false
            return
        }
        if let message = commit(trimmed) {
            if keepOnError {
                error = message
                focused = true
                return
            }
        }
        error = nil
        isEditing = false
    }
}

// MARK: Language

/// The language or original language of the detail's meta line: a menu with
/// the same choices as the editor's popup.
struct InlineLanguageMenu: View {
    @Environment(\.locale) private var locale
    var code: String?
    /// What shows when a language is set ("German", "Original: Japanese").
    var display: String
    var placeholder: LocalizedStringKey
    var usedLanguages: [String]
    var revealsEmpty: Bool
    var select: (String?) -> Void

    @State private var isHovered = false

    var body: some View {
        if code != nil || revealsEmpty {
            let options = LanguageOptions.codes(used: usedLanguages, locale: locale)
            Menu {
                Picker(placeholder, selection: Binding(get: { code }, set: { select($0) })) {
                    Text("None").tag(String?.none)
                    if !options.used.isEmpty {
                        Divider()
                        ForEach(options.used, id: \.self) { code in
                            Text(LanguageOptions.name(code, locale)).tag(String?.some(code))
                        }
                    }
                    Divider()
                    ForEach(options.others, id: \.self) { code in
                        Text(LanguageOptions.name(code, locale)).tag(String?.some(code))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                (code == nil ? Text(placeholder) : Text(verbatim: display))
                    .foregroundStyle(code == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 3)
            .background {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            }
            .padding(.horizontal, -3)
            .onHover { isHovered = $0 }
            .accessibilityLabel(Text(placeholder))
        }
    }
}

// MARK: Date Added

/// "Added 3 Oct 2026": clicking opens a calendar, like the editor's Date Added.
struct InlineAddedDate: View {
    @Environment(\.locale) private var locale
    var date: Date
    /// "Added 3 Oct 2026", from `BookFormatting.added`.
    var display: String
    var select: (Date) -> Void

    @State private var isOpen = false
    @State private var isHovered = false

    var body: some View {
        let formatting = BookFormatting(locale: locale)
        Text(verbatim: display)
            .padding(.horizontal, 3)
            .background {
                RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            }
            .padding(.horizontal, -3)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture { isOpen = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Date Added"))
            .accessibilityValue(formatting.day(date))
            .accessibilityAction { isOpen = true }
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                DatePicker("Date Added", selection: Binding(
                    get: { date },
                    set: { picked in
                        select(Calendar.current.startOfDay(for: picked))
                        isOpen = false
                    }
                ), in: Date.distantPast...Date.now, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(12)
            }
    }
}
