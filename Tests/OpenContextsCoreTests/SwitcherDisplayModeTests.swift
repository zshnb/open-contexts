import XCTest
@testable import OpenContextsCore

final class SwitcherDisplayModeTests: XCTestCase {
    func testAllDisplaysPreservesEveryDisplayInScreenOrder() {
        XCTAssertEqual(SwitcherDisplayMode.allDisplays.targetDisplays(from: [42, 7, 99]), [42, 7, 99])
    }

    func testPrimaryDisplaySelectsOnlyTheFirstDisplay() {
        XCTAssertEqual(SwitcherDisplayMode.primaryDisplay.targetDisplays(from: ["primary", "external"]), ["primary"])
    }

    func testBothModesSelectTheOnlyDisplay() {
        for mode in SwitcherDisplayMode.allCases {
            XCTAssertEqual(mode.targetDisplays(from: [42]), [42])
        }
    }

    func testBothModesHandleNoDisplays() {
        for mode in SwitcherDisplayMode.allCases {
            XCTAssertEqual(mode.targetDisplays(from: [Int]()), [])
        }
    }

    func testPersistedRawValuesRemainStable() {
        XCTAssertEqual(SwitcherDisplayMode.allDisplays.rawValue, "allDisplays")
        XCTAssertEqual(SwitcherDisplayMode.primaryDisplay.rawValue, "primaryDisplay")
        XCTAssertEqual(SwitcherDisplayMode(rawValue: "allDisplays"), .allDisplays)
        XCTAssertEqual(SwitcherDisplayMode(rawValue: "primaryDisplay"), .primaryDisplay)
    }

    func testUnknownRawValueIsRejected() {
        XCTAssertNil(SwitcherDisplayMode(rawValue: "invalid"))
    }

    func testFocusedDisplaySelectsTheFocusedScreen() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [42, 7, 99], focused: 7), [7])
    }

    func testFocusedDisplayFallsBackToPrimaryWithoutFocus() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [42, 7, 99]), [42])
    }

    func testFocusedDisplayFallsBackToPrimaryWhenFocusedScreenWasRemoved() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [42, 7], focused: 99), [42])
    }

    func testFocusedDisplayHandlesNoScreensEvenWithFocus() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [Int](), focused: 7), [])
    }

    func testAllDisplaysIgnoresFocusedScreen() {
        XCTAssertEqual(SwitcherDisplayMode.allDisplays.targetDisplays(from: [42, 7, 99], focused: 7), [42, 7, 99])
    }

    func testPrimaryDisplayIgnoresFocusedScreen() {
        XCTAssertEqual(SwitcherDisplayMode.primaryDisplay.targetDisplays(from: [42, 7, 99], focused: 7), [42])
    }

    func testFocusedDisplayPersistedRawValueRemainsStable() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.rawValue, "focusedDisplay")
        XCTAssertEqual(SwitcherDisplayMode(rawValue: "focusedDisplay"), .focusedDisplay)
    }

    func testWindowFullyInsideSecondDisplaySelectsIt() {
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 120, y: 10, width: 50, height: 80), in: sideBySideDisplays
        ), "external")
    }

    func testSpanningWindowSelectsDisplayWithLargerOverlap() {
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 75, y: 10, width: 100, height: 80), in: sideBySideDisplays
        ), "external")
    }

    func testEqualOverlapSelectsEarlierDisplay() {
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 50, y: 10, width: 100, height: 80), in: sideBySideDisplays
        ), "primary")
    }

    func testWindowOutsideAllDisplaysHasNoDisplay() {
        XCTAssertNil(SwitcherDisplayMode.display(
            containing: CGRect(x: 400, y: 10, width: 50, height: 80), in: sideBySideDisplays
        ))
    }

    func testWindowTouchingDisplayEdgeHasNoOverlap() {
        XCTAssertNil(SwitcherDisplayMode.display(
            containing: CGRect(x: 200, y: 10, width: 50, height: 80), in: sideBySideDisplays
        ))
    }

    func testWindowCanMatchDisplaysAtNegativeCoordinates() {
        let displays = [
            (id: "primary", bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (id: "left", bounds: CGRect(x: -100, y: 0, width: 100, height: 100)),
            (id: "above", bounds: CGRect(x: 0, y: -100, width: 100, height: 100))
        ]
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: -75, y: 25, width: 50, height: 50), in: displays
        ), "left")
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 25, y: -75, width: 50, height: 50), in: displays
        ), "above")
    }

    func testWindowHasNoDisplayWhenScreenListIsEmpty() {
        let displays: [(id: Int, bounds: CGRect)] = []
        XCTAssertNil(SwitcherDisplayMode.display(
            containing: CGRect(x: 0, y: 0, width: 50, height: 50), in: displays
        ))
    }

    private var sideBySideDisplays: [(id: String, bounds: CGRect)] {
        [
            (id: "primary", bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (id: "external", bounds: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]
    }
}
