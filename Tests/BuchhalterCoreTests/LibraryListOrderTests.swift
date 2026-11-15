import Foundation
import Testing
@testable import BuchhalterCore

struct LibraryListOrderTests {
    @Test func defaultOrder() {
        #expect(LibraryListOrder().lists == [.reading, .wantToRead, .read, .all])
        #expect(LibraryListOrder(raw: "").lists == [.reading, .wantToRead, .read, .all])
    }

    @Test func rawRoundTripAndRepair() {
        var order = LibraryListOrder()
        order.move(fromOffsets: [3], toOffset: 0)
        #expect(order.raw == "all,reading,wantToRead,read")
        #expect(LibraryListOrder(raw: order.raw) == order)
        #expect(LibraryListOrder(raw: "read,nonsense,read,collection:\(UUID().uuidString)").lists == [.read, .reading, .wantToRead, .all])
    }

    @Test func movesLikeAList() {
        var order = LibraryListOrder()
        order.move(fromOffsets: [0], toOffset: 4)
        #expect(order.lists == [.wantToRead, .read, .all, .reading])
        order.move(fromOffsets: [2], toOffset: 1)
        #expect(order.lists == [.wantToRead, .all, .read, .reading])
        order.move(fromOffsets: [0, 1], toOffset: 3)
        #expect(order.lists == [.read, .wantToRead, .all, .reading])
    }
}
