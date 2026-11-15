import Foundation

/// What is known about the saved Google Books key. It is stored in
/// UserDefaults (it is not a secret) so the Settings pane can show the right
/// line after a relaunch.
public enum GoogleBooksKeyState: String, Sendable {
    /// Saved without a check ("Save Anyway"); the first lookup that reaches Google Books checks it.
    case unchecked
    /// A check or a lookup succeeded with this key.
    case works
    /// Google refused the key in a lookup.
    case rejected

    /// The state after a lookup event. Only Google Books events count, and
    /// only an answer or a refused key: an unreachable service says nothing
    /// about the key.
    public func after(_ event: LookupEvent) -> GoogleBooksKeyState {
        switch event {
        case .answered(.googleBooks): .works
        case .failed(.googleBooks, .keyRejected): .rejected
        default: self
        }
    }
}

/// The line under the masked key in Settings. The views map each case to its
/// text, one literal catalog key per case.
public enum GoogleBooksKeyLine: Equatable, Sendable {
    /// Just saved and switched on, Google Books in last place.
    case nowOnAsLast
    /// Just saved and switched on, dragged elsewhere before.
    case nowOn
    case isOn
    case isOff
    case savedNotChecked
    case rejected

    public static func line(state: GoogleBooksKeyState, isOn: Bool, justSaved: Bool, isLast: Bool) -> GoogleBooksKeyLine {
        switch state {
        case .rejected: .rejected
        case .unchecked: .savedNotChecked
        case .works:
            if !isOn { .isOff } else if justSaved { isLast ? .nowOnAsLast : .nowOn } else { .isOn }
        }
    }
}
