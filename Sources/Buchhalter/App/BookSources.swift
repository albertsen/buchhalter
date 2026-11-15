import Foundation
import Observation
import BuchhalterCore

/// What came of saving a key in Settings.
enum KeySaveOutcome {
    case saved
    case rejected
    /// The check could not reach Google Books; the key is not saved yet.
    case offline
    /// The Keychain refused the write; `BookSources.keychainError` says so.
    case keychainFailed
}

/// The app-wide state of the book sources: the user's order and switches, and
/// the Google Books key. One instance is created by `BuchhalterApp` and shared
/// with the main window and Settings, so switching a source in Settings
/// enables or disables Complete and Find Cover in an open sheet at once. The
/// full key is never held here: the Keychain has it, and only the last four
/// characters live in memory.
///
/// Order and switches (`lookupSources`) and the key's state
/// (`googleBooksKeyState`) are per-Mac preferences in UserDefaults; the key
/// state is no secret.
@Observable
final class BookSources {
    private(set) var list: LookupSourceList
    /// Nil while no key is saved.
    private(set) var keyState: GoogleBooksKeyState?
    private(set) var hasGoogleKey = false
    private(set) var keySuffix: String?
    /// Shown in Settings when the Keychain refuses a write.
    var keychainError: String?
    /// The key was saved in this Settings window's lifetime: its line then
    /// says "is now on" instead of "is on". The Mac Settings window clears it
    /// when it closes.
    var justSavedKey = false

    @ObservationIgnored private let store = KeychainSecretStore()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let dnb = DNBService()
    @ObservationIgnored private let openLibrary = OpenLibraryService()
    @ObservationIgnored private lazy var googleBooks = GoogleBooksService(keys: store)

    private static let listKey = "lookupSources"
    private static let stateKey = "googleBooksKeyState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        list = LookupSourceList(raw: defaults.string(forKey: Self.listKey) ?? "")
        keyState = defaults.string(forKey: Self.stateKey).flatMap(GoogleBooksKeyState.init(rawValue:))
    }

    // MARK: Derived

    /// The sources that are on, in the user's order. Google Books counts only
    /// with a saved key; a missing key never flips its switch.
    var lookup: BookLookup {
        let services: [any BookLookupService] = list.active(hasGoogleKey: hasGoogleKey).map { source in
            switch source {
            case .dnb: dnb
            case .openLibrary: openLibrary
            case .googleBooks: googleBooks
            }
        }
        return BookLookup(services: services, observer: { [weak self] event in self?.record(event) })
    }

    var hasActiveSource: Bool { !list.active(hasGoogleKey: hasGoogleKey).isEmpty }

    /// Find Cover's "No cover found" alert points to Settings when Google
    /// Books has no key or is off.
    var suggestsGoogleBooks: Bool { !hasGoogleKey || !list.isOn(.googleBooks) }

    // MARK: Launch

    /// Asks whether a key exists, which does not read it and so shows no
    /// permission prompt. A key without a recorded state (added with the
    /// `security` tool) counts as unchecked.
    func refreshKey() async {
        hasGoogleKey = await store.exists()
        if !hasGoogleKey {
            setKeyState(nil)
            keySuffix = nil
        } else if keyState == nil {
            setKeyState(.unchecked)
        }
    }

    /// The masked key's last four characters. Reading them can mean reading
    /// the secret (an item without the comment attribute), so Settings asks
    /// for it only when it shows the key.
    func loadKeySuffix() async {
        guard hasGoogleKey, keySuffix == nil else { return }
        keySuffix = await store.suffix()
    }

    // MARK: Sources

    func setOn(_ source: LookupSource, _ isOn: Bool) {
        list.setOn(source, isOn)
        defaults.set(list.raw, forKey: Self.listKey)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        list.move(fromOffsets: source, toOffset: destination)
        defaults.set(list.raw, forKey: Self.listKey)
    }

    // MARK: Key

    /// Checks the key with one search at Google Books, and saves it only when
    /// Google accepts it. The old key stays in use until then. On success
    /// Google Books is switched on where it stands.
    func saveKey(_ text: String) async -> KeySaveOutcome {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch await GoogleBooksService.checkKey(key) {
        case .rejected: return .rejected
        case .unreachable: return .offline
        case .works: return await keep(key, state: .works)
        }
    }

    /// "Save Anyway": no check, treated like a working key until a lookup says otherwise.
    func saveKeyWithoutCheck(_ text: String) async -> KeySaveOutcome {
        await keep(text.trimmingCharacters(in: .whitespacesAndNewlines), state: .unchecked)
    }

    private func keep(_ key: String, state: GoogleBooksKeyState) async -> KeySaveOutcome {
        do {
            try await store.save(key)
        } catch {
            keychainError = String(localized: "The key couldn't be saved in the Keychain.")
            return .keychainFailed
        }
        keychainError = nil
        justSavedKey = true
        hasGoogleKey = true
        keySuffix = String(key.suffix(4))
        setKeyState(state)
        setOn(.googleBooks, true)
        return .saved
    }

    /// Deletes the key at once and switches Google Books off. It keeps its place in the list.
    func removeKey() async {
        do {
            try await store.delete()
        } catch {
            keychainError = String(localized: "The key couldn't be removed from the Keychain.")
            return
        }
        keychainError = nil
        justSavedKey = false
        hasGoogleKey = false
        keySuffix = nil
        setKeyState(nil)
        setOn(.googleBooks, false)
    }

    // MARK: Events

    /// Every lookup reports what happened to each source; Google Books'
    /// answer or refusal updates the key's state.
    func record(_ event: LookupEvent) {
        guard hasGoogleKey, let state = keyState else { return }
        let next = state.after(event)
        if next != state { setKeyState(next) }
    }

    private func setKeyState(_ state: GoogleBooksKeyState?) {
        keyState = state
        if let state {
            defaults.set(state.rawValue, forKey: Self.stateKey)
        } else {
            defaults.removeObject(forKey: Self.stateKey)
        }
    }
}
