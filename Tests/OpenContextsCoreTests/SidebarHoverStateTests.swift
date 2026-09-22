import CoreGraphics
import XCTest
@testable import OpenContextsCore

final class SidebarHoverStateTests: XCTestCase {
    private let edge = CGRect(x: 992, y: 300, width: 8, height: 200)
    private let expanded = CGRect(x: 740, y: 300, width: 260, height: 200)

    func testEdgeExpansionStaysOpenAcrossResizeEventsAndDelayedExit() {
        var state = SidebarHoverState()
        XCTAssertTrue(state.update(pointer: CGPoint(x: 996, y: 400), edgeFrame: edge,
                                   expandedFrame: expanded, dragging: false, now: 0))
        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.update(pointer: CGPoint(x: 900, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 0.01))
        XCTAssertFalse(state.update(pointer: CGPoint(x: 900, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 1))

        XCTAssertFalse(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 2))
        XCTAssertFalse(state.update(pointer: CGPoint(x: 900, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 2.05))
        XCTAssertFalse(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 3))
        XCTAssertTrue(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                   expandedFrame: expanded, dragging: false, now: 3.12))
        XCTAssertFalse(state.isExpanded)
    }

    func testReentryCancelsCollapseAndDraggingKeepsExpanded() {
        var state = SidebarHoverState(isExpanded: true)
        XCTAssertFalse(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 0))
        XCTAssertFalse(state.update(pointer: CGPoint(x: 900, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 0.1))
        XCTAssertFalse(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 1))
        XCTAssertFalse(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: true, now: 2))
        XCTAssertTrue(state.isExpanded)
        XCTAssertFalse(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                    expandedFrame: expanded, dragging: false, now: 3))
        XCTAssertTrue(state.update(pointer: CGPoint(x: 700, y: 400), edgeFrame: edge,
                                   expandedFrame: expanded, dragging: false, now: 3.12))
        XCTAssertFalse(state.isExpanded)
    }
}
