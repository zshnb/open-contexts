import XCTest
@testable import OpenContextsCore

final class RecentWindowOrderTests: XCTestCase {
    private let ids = ["A", "B", "C"]

    private func focused(on id: String) -> RecentWindowOrder {
        var order = RecentWindowOrder()
        order.update(windowIDs: ids, focusedID: id, now: 0)
        return order
    }

    func testFocusMovesWindowToFrontAndKeepsOthersInOrder() {
        var order = focused(on: "A")
        order.update(windowIDs: ids + ["D"], focusedID: "C", now: 1)
        XCTAssertEqual(order.ids, ["C", "A", "B", "D"])
        order.update(windowIDs: ["B", "C", "D"], focusedID: nil, now: 2)
        XCTAssertEqual(order.ids, ["C", "B", "D"])
        XCTAssertNil(order.focusedID)
    }

    func testFocusChangesDuringRequestedSwitchDoNotDisplacePreviousWindow() {
        var order = focused(on: "A")
        order.beginActivation("B")
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        // Before B gets focus the scan still sees A; the desktop switch then briefly restores C.
        order.update(windowIDs: ids, focusedID: "A", now: 0.1)
        order.update(windowIDs: ids, focusedID: "C", now: 0.3)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        XCTAssertEqual(order.focusedID, "B")
        order.finishActivation(now: 1.5)
        order.update(windowIDs: ids, focusedID: "B", now: 1.6)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        order.update(windowIDs: ids, focusedID: "C", now: 2)
        XCTAssertEqual(order.ids, ["C", "B", "A"])
    }

    func testCancelledSwitchRecordsFocusAgain() {
        var order = focused(on: "A")
        order.beginActivation("B")
        order.cancelActivation()
        order.update(windowIDs: ids, focusedID: "C", now: 0.2)
        XCTAssertEqual(order.ids, ["C", "B", "A"])
    }

    func testSwitchThatNeverGetsFocusStopsHoldingAfterTimeout() {
        var order = focused(on: "A")
        order.beginActivation("B")
        order.finishActivation(now: 1)
        order.update(windowIDs: ids, focusedID: "A", now: 1.2)
        XCTAssertEqual(order.ids, ["B", "A", "C"])
        order.update(windowIDs: ids, focusedID: "A", now: 2)
        XCTAssertEqual(order.ids, ["A", "B", "C"])
        XCTAssertEqual(order.focusedID, "A")
    }
}
