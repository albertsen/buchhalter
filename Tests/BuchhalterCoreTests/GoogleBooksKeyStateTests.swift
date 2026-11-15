import Foundation
import Testing
@testable import BuchhalterCore

struct GoogleBooksKeyStateTests {
    // MARK: Transitions

    @Test func anAnswerFromGoogleBooksMeansTheKeyWorks() {
        #expect(GoogleBooksKeyState.unchecked.after(.answered(.googleBooks)) == .works)
        #expect(GoogleBooksKeyState.rejected.after(.answered(.googleBooks)) == .works)
        #expect(GoogleBooksKeyState.works.after(.answered(.googleBooks)) == .works)
    }

    @Test func aRefusedKeyMeansRejected() {
        #expect(GoogleBooksKeyState.works.after(.failed(.googleBooks, .keyRejected(.googleBooks))) == .rejected)
        #expect(GoogleBooksKeyState.unchecked.after(.failed(.googleBooks, .keyRejected(.googleBooks))) == .rejected)
    }

    @Test func anUnreachableServiceSaysNothingAboutTheKey() {
        for state in [GoogleBooksKeyState.works, .unchecked, .rejected] {
            #expect(state.after(.failed(.googleBooks, .unreachable(.googleBooks))) == state)
            #expect(state.after(.asking(.googleBooks)) == state)
        }
    }

    @Test func otherSourcesDoNotChangeIt() {
        for state in [GoogleBooksKeyState.works, .unchecked, .rejected] {
            #expect(state.after(.answered(.dnb)) == state)
            #expect(state.after(.failed(.openLibrary, .keyRejected(.openLibrary))) == state)
        }
    }

    @Test func rawValuesAreStable() {
        #expect(GoogleBooksKeyState(rawValue: "works") == .works)
        #expect(GoogleBooksKeyState(rawValue: "unchecked") == .unchecked)
        #expect(GoogleBooksKeyState(rawValue: "rejected") == .rejected)
        #expect(GoogleBooksKeyState(rawValue: "other") == nil)
    }

    // MARK: Line

    @Test func theLineAfterSavingNamesThePlace() {
        #expect(GoogleBooksKeyLine.line(state: .works, isOn: true, justSaved: true, isLast: true) == .nowOnAsLast)
        #expect(GoogleBooksKeyLine.line(state: .works, isOn: true, justSaved: true, isLast: false) == .nowOn)
    }

    @Test func theLineWhenTheWindowIsOpenedLater() {
        #expect(GoogleBooksKeyLine.line(state: .works, isOn: true, justSaved: false, isLast: true) == .isOn)
        #expect(GoogleBooksKeyLine.line(state: .works, isOn: false, justSaved: false, isLast: true) == .isOff)
        // Switched off right after saving: the line says so.
        #expect(GoogleBooksKeyLine.line(state: .works, isOn: false, justSaved: true, isLast: true) == .isOff)
    }

    @Test func anUncheckedKeyAndARejectedKeyHaveTheirOwnLines() {
        for justSaved in [true, false] {
            for isOn in [true, false] {
                #expect(GoogleBooksKeyLine.line(state: .unchecked, isOn: isOn, justSaved: justSaved, isLast: true) == .savedNotChecked)
                #expect(GoogleBooksKeyLine.line(state: .rejected, isOn: isOn, justSaved: justSaved, isLast: false) == .rejected)
            }
        }
    }
}
