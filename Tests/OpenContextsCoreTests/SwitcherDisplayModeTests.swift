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
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [42, 7, 99], anchor: 7), [7])
    }

    func testFocusedDisplayFallsBackToPrimaryWithoutFocus() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [42, 7, 99]), [42])
    }

    func testFocusedDisplayFallsBackToPrimaryWhenFocusedScreenWasRemoved() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [42, 7], anchor: 99), [42])
    }

    func testFocusedDisplayHandlesNoScreensEvenWithFocus() {
        XCTAssertEqual(SwitcherDisplayMode.focusedDisplay.targetDisplays(from: [Int](), anchor: 7), [])
    }

    func testAllDisplaysIgnoresFocusedScreen() {
        XCTAssertEqual(SwitcherDisplayMode.allDisplays.targetDisplays(from: [42, 7, 99], anchor: 7), [42, 7, 99])
    }

    func testPrimaryDisplayIgnoresFocusedScreen() {
        XCTAssertEqual(SwitcherDisplayMode.primaryDisplay.targetDisplays(from: [42, 7, 99], anchor: 7), [42])
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

    func testPointerDisplaySelectsAnchorOnThirdScreen() {
        XCTAssertEqual(SwitcherDisplayMode.pointerDisplay.targetDisplays(from: [42, 7, 99], anchor: 99), [99])
    }

    func testPointerDisplayFallsBackToPrimaryWithoutAnchor() {
        XCTAssertEqual(SwitcherDisplayMode.pointerDisplay.targetDisplays(from: [42, 7, 99]), [42])
    }

    func testPointerDisplayFallsBackToPrimaryWhenAnchorScreenWasRemoved() {
        XCTAssertEqual(SwitcherDisplayMode.pointerDisplay.targetDisplays(from: [42, 7, 99], anchor: 123), [42])
    }

    func testPointerDisplayHandlesNoScreensEvenWithAnchor() {
        XCTAssertEqual(SwitcherDisplayMode.pointerDisplay.targetDisplays(from: [Int](), anchor: 99), [])
    }

    func testPointerDisplayPersistedRawValueRemainsStable() {
        XCTAssertEqual(SwitcherDisplayMode.pointerDisplay.rawValue, "pointerDisplay")
        XCTAssertEqual(SwitcherDisplayMode(rawValue: "pointerDisplay"), .pointerDisplay)
    }

    func testOnlyFocusedAndPointerModesUseAnAnchorDisplay() {
        XCTAssertFalse(SwitcherDisplayMode.allDisplays.usesAnchorDisplay)
        XCTAssertFalse(SwitcherDisplayMode.primaryDisplay.usesAnchorDisplay)
        XCTAssertTrue(SwitcherDisplayMode.focusedDisplay.usesAnchorDisplay)
        XCTAssertTrue(SwitcherDisplayMode.pointerDisplay.usesAnchorDisplay)
    }

    func testDisplayModeOrderMatchesSettingsOptions() {
        XCTAssertEqual(SwitcherDisplayMode.allCases, [.allDisplays, .primaryDisplay, .focusedDisplay, .pointerDisplay])
    }

    func testPointerRectangleInsideThirdDisplaySelectsIt() {
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 250, y: 50, width: 1, height: 1), in: threeDisplays
        ), "third")
    }

    func testPointerRectangleAtDisplayTopLeftSelectsIt() {
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 100, y: 0, width: 1, height: 1), in: threeDisplays
        ), "external")
    }

    func testPointerRectangleAtDisplayBottomRightPixelSelectsIt() {
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 199, y: 99, width: 1, height: 1), in: threeDisplays
        ), "external")
    }

    func testPointerRectangleCanMatchDisplaysAtNegativeCoordinates() {
        let displays = [
            (id: "primary", bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (id: "left", bounds: CGRect(x: -100, y: 0, width: 100, height: 100)),
            (id: "above", bounds: CGRect(x: 0, y: -100, width: 100, height: 100))
        ]
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: -1, y: 0, width: 1, height: 1), in: displays
        ), "left")
        XCTAssertEqual(SwitcherDisplayMode.display(
            containing: CGRect(x: 0, y: -1, width: 1, height: 1), in: displays
        ), "above")
    }

    private var threeDisplays: [(id: String, bounds: CGRect)] {
        sideBySideDisplays + [(id: "third", bounds: CGRect(x: 200, y: 0, width: 100, height: 100))]
    }

    private var sideBySideDisplays: [(id: String, bounds: CGRect)] {
        [
            (id: "primary", bounds: CGRect(x: 0, y: 0, width: 100, height: 100)),
            (id: "external", bounds: CGRect(x: 100, y: 0, width: 100, height: 100))
        ]
    }
}
