import Foundation
import Testing
@testable import BuchhalterCore

struct LookupSourceListTests {
    private func order(_ list: LookupSourceList) -> [LookupSource] { list.entries.map(\.source) }

    @Test func aNewUserHasDNBThenOpenLibraryOnAndGoogleBooksLastAndOff() {
        let list = LookupSourceList()
        #expect(order(list) == [.dnb, .openLibrary, .googleBooks])
        #expect(list.entries.map(\.isOn) == [true, true, false])
        #expect(list.raw == "dnb:on,openLibrary:on,googleBooks:off")
        #expect(list.isGoogleBooksLast)
    }

    @Test func theRawValueRoundTrips() {
        var list = LookupSourceList()
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        list.setOn(.openLibrary, false)
        list.setOn(.googleBooks, true)
        #expect(list.raw == "googleBooks:on,dnb:on,openLibrary:off")
        #expect(LookupSourceList(raw: list.raw) == list)
        #expect(LookupSourceList(raw: "") == LookupSourceList())
    }

    @Test func damagedValuesNeverHideASource() {
        // Unknown and repeated entries are dropped, missing ones come back with their default switch.
        let list = LookupSourceList(raw: "openLibrary:off,bing:on,openLibrary:on,dnb:maybe")
        #expect(order(list) == [.openLibrary, .dnb, .googleBooks])
        #expect(list.entries.map(\.isOn) == [false, true, false])
        #expect(order(LookupSourceList(raw: "garbage")) == [.dnb, .openLibrary, .googleBooks])
        #expect(LookupSourceList(raw: "googleBooks").isOn(.googleBooks) == false)
    }

    @Test func moveFollowsTheOnMoveContract() {
        var list = LookupSourceList()
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(order(list) == [.openLibrary, .googleBooks, .dnb])
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(order(list) == [.dnb, .openLibrary, .googleBooks])
        // Moving onto its own place changes nothing.
        list.move(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        list.move(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        #expect(order(list) == [.dnb, .openLibrary, .googleBooks])
        list.move(fromOffsets: IndexSet(integer: 5), toOffset: 0)
        #expect(order(list) == [.dnb, .openLibrary, .googleBooks])
        #expect(list.entries.map(\.isOn) == [true, true, false])
    }

    @Test func moveKeepsTheSwitches() {
        var list = LookupSourceList()
        list.setOn(.openLibrary, false)
        list.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        #expect(order(list) == [.openLibrary, .dnb, .googleBooks])
        #expect(list.entries.map(\.isOn) == [false, true, false])
    }

    @Test func activeExcludesGoogleBooksWithoutAKeyButKeepsItsSwitch() {
        var list = LookupSourceList()
        list.setOn(.googleBooks, true)
        #expect(list.active(hasGoogleKey: false) == [.dnb, .openLibrary])
        #expect(list.active(hasGoogleKey: true) == [.dnb, .openLibrary, .googleBooks])
        #expect(list.isOn(.googleBooks))
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(list.active(hasGoogleKey: true) == [.googleBooks, .dnb, .openLibrary])
        #expect(!list.isGoogleBooksLast)
    }

    @Test func switchesDecideWhatIsActive() {
        var list = LookupSourceList()
        list.setOn(.dnb, false)
        list.setOn(.openLibrary, false)
        #expect(list.active(hasGoogleKey: true).isEmpty)
        list.setOn(.openLibrary, true)
        #expect(list.active(hasGoogleKey: true) == [.openLibrary])
    }
}
