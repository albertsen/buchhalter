import SwiftUI
import BuchhalterCore

/// The Google Books key in Settings: entering and checking it, the masked key
/// with Change… and Remove, and the line that says what is known about it.
/// The key itself never leaves the field: `BookSources` checks it, hands it to
/// the Keychain and keeps only its last four characters.
struct GoogleBooksKeySection: View {
    @Environment(BookSources.self) private var sources

    private enum Phase {
        case entering, checking, rejected, offline
    }

    @State private var phase = Phase.entering
    @State private var text = ""
    /// Change… was pressed: an empty field replaces the masked key until a new key checks out.
    @State private var isChanging = false
    @State private var showsHelp = false

    private var showsMasked: Bool { sources.hasGoogleKey && !isChanging }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .checking }
    /// The mask is the length of a Google key without its last four characters.
    private var masked: String { String(repeating: "•", count: 17) + (sources.keySuffix ?? "") }
    private let indent: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsMasked { savedRow } else { entryRow }
            if let error = sources.keychainError {
                SettingsHint(tone: .error, message: Text(verbatim: error)).padding(.leading, indent)
            }
            if showsMasked { savedLines } else { entryLines }
        }
        .task { await sources.loadKeySuffix() }
        .onChange(of: text) {
            if phase == .rejected || phase == .offline { phase = .entering }
        }
        .sheet(isPresented: $showsHelp) { GoogleBooksKeyHelpSheet() }
    }

    // MARK: Saved key

    private var savedRow: some View {
        HStack(spacing: 8) {
            label
            Text(verbatim: masked)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("API Key"))
                .accessibilityValue(Text(verbatim: sources.keySuffix.map { "…\($0)" } ?? ""))
            Spacer(minLength: 8)
            Button("Change…") {
                text = ""
                phase = .entering
                isChanging = true
            }
            Button("Remove") { remove() }
        }
    }

    @ViewBuilder
    private var savedLines: some View {
        let line = GoogleBooksKeyLine.line(
            state: sources.keyState ?? .unchecked, isOn: sources.list.isOn(.googleBooks),
            justSaved: sources.justSavedKey, isLast: sources.list.isGoogleBooksLast
        )
        VStack(alignment: .leading, spacing: 6) {
            switch line {
            case .nowOnAsLast:
                SettingsHint(tone: .success, systemImage: "checkmark", message: Text("The key works. Google Books is now on, as the last source."))
            case .nowOn:
                SettingsHint(tone: .success, systemImage: "checkmark", message: Text("The key works. Google Books is now on."))
            case .isOn:
                SettingsHint(tone: .success, systemImage: "checkmark", message: Text("The key works. Google Books is on."))
            case .isOff:
                SettingsHint(tone: .success, systemImage: "checkmark", message: Text("The key works. Google Books is off."))
            case .savedNotChecked:
                SettingsHint(tone: .neutral, message: Text("The key is saved but not checked yet."))
            case .rejected:
                SettingsHint(tone: .error, message: Text("Google didn't accept the key. Check it or enter a new one."))
            }
            poweredBy
        }
        .padding(.leading, indent - 2)
    }

    private var poweredBy: some View {
        // Google's name for its attribution: stays in English in both languages.
        Text(verbatim: "Powered by Google")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    // MARK: Entry

    private var label: some View {
        Text("API Key")
            .font(.system(size: 13))
            .frame(width: 70, alignment: .trailing)
    }

    private var entryRow: some View {
        HStack(spacing: 8) {
            label
            SecureField("Paste your key", text: $text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .disabled(phase == .checking)
                .onSubmit(save)
                .overlay {
                    if phase == .rejected {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.error, lineWidth: 1.5)
                    }
                }
                .accessibilityLabel("API Key")
            if phase == .checking {
                Button {} label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                }
                .disabled(true)
            } else {
                if isChanging {
                    Button("Cancel") { cancelChange() }
                        .keyboardShortcut(.cancelAction)
                }
                Button("Save Key", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
    }

    @ViewBuilder
    private var entryLines: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch phase {
            case .checking:
                Text("Saving checks the key with one search at Google Books.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            case .rejected:
                SettingsHint(
                    tone: .error,
                    message: Text("Google didn't accept this key. Check that you copied all of it and that the Books API is turned on for it. The key was not saved.")
                )
            case .offline:
                SettingsHint(tone: .warning, message: Text("Can't reach Google Books to check the key. Check the internet connection.")) {
                    Button { saveAnyway() } label: { Text("Save Anyway").underline() }
                        .buttonStyle(.plain)
                }
            case .entering:
                EmptyView()
            }
            Button("How to get a key…") { showsHelp = true }
                .buttonStyle(.link)
                .font(.system(size: 12))
            Text("The key is stored in your Keychain. Searches send the book's ISBN, or its title and author, to Google.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, indent)
    }

    // MARK: Actions

    private func save() {
        guard canSave else { return }
        phase = .checking
        let entered = text
        Task { finish(await sources.saveKey(entered)) }
    }

    /// "Save Anyway": the check could not run, so the key is saved unchecked.
    private func saveAnyway() {
        let entered = text
        Task { finish(await sources.saveKeyWithoutCheck(entered)) }
    }

    private func finish(_ outcome: KeySaveOutcome) {
        switch outcome {
        case .saved:
            text = ""
            isChanging = false
            phase = .entering
        case .rejected:
            phase = .rejected
        case .offline:
            phase = .offline
        case .keychainFailed:
            phase = .entering
        }
    }

    private func cancelChange() {
        text = ""
        phase = .entering
        isChanging = false
    }

    private func remove() {
        Task {
            await sources.removeKey()
            text = ""
            phase = .entering
            isChanging = false
        }
    }
}
