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
}
