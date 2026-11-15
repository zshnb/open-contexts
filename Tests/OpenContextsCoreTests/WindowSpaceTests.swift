import XCTest
@testable import OpenContextsCore

final class WindowSpaceTests: XCTestCase {
    private func window(_ id: String, app: String, space: WindowSpace?) -> WindowInfo {
        WindowInfo(id: id, appID: app, appName: app, title: "Project", processID: 1, space: space)
    }

    func testCurrentDesktopIsFirstAndKeepsRecentOrder() {
        let current = WindowSpace(id: 30, index: 3, isCurrent: true)
        let other = WindowSpace(id: 10, index: 1, isCurrent: false)
        let windows = [window("old-other", app: "Zulu", space: other),
                       window("recent", app: "Zulu", space: current),
                       window("older", app: "Alpha", space: current),
                       window("new-other", app: "Alpha", space: other)]
        XCTAssertEqual(WindowSwitcher.filter(windows, query: "", allSpaces: true).map(\.window.id),
                       ["recent", "older", "new-other", "old-other"])
        XCTAssertEqual(WindowSwitcher.filter(windows, query: "", allSpaces: false).map(\.window.id),
                       ["recent", "older"])
    }

    func testOtherDesktopsIgnoreRecentOrderAndFollowDesktopIndex() {
        let first = WindowSpace(id: 50, index: 1, isCurrent: false)
        let second = WindowSpace(id: 10, index: 2, isCurrent: false)
        let windows = [window("b", app: "Zulu", space: first), window("c", app: "Alpha", space: second),
                       window("a", app: "Alpha", space: first)]
        let expected = ["a", "b", "c"]
        XCTAssertEqual(WindowSwitcher.filter(windows, query: "", allSpaces: true).map(\.window.id), expected)
        XCTAssertEqual(WindowSwitcher.filter(windows.reversed(), query: "", allSpaces: true).map(\.window.id), expected)
    }

    func testSearchKeepsCurrentDesktopAheadOfStrongerOtherDesktopMatch() {
        let current = WindowSpace(id: 2, index: 2, isCurrent: true)
        let other = WindowSpace(id: 1, index: 1, isCurrent: false)
        let windows = [window("other", app: "Code", space: other), window("current", app: "My Code", space: current)]
        let results = WindowSwitcher.filter(windows, query: "code", allSpaces: true)
        XCTAssertEqual(results.map(\.window.id), ["current", "other"])
        XCTAssertFalse(results[0].appRanges.isEmpty)
        XCTAssertTrue(WindowSwitcher.filter(windows, query: "missing", allSpaces: true).isEmpty)
    }

    func testQuickSwitchSelectsPreviousWindowOnAnotherDesktop() {
        let current = WindowSpace(id: 2, index: 2, isCurrent: true)
        let other = WindowSpace(id: 1, index: 1, isCurrent: false)
        // Most recent first: just switched from A (other desktop) to B; C is older on the current desktop.
        let windows = [window("B", app: "Beta", space: current), window("A", app: "Alpha", space: other),
                       window("C", app: "Gamma", space: current)]
        let start = WindowSwitcher.start(windows, allSpaces: true, focusedID: "B", reverse: false)
        XCTAssertEqual(start.results.map(\.window.id), ["B", "C", "A"])
        XCTAssertEqual(start.results[start.selectedIndex].window.id, "A")
    }

    func testStartSelectionWithoutOtherDesktopsOrFocus() {
        let current = WindowSpace(id: 2, index: 2, isCurrent: true)
        let other = WindowSpace(id: 1, index: 1, isCurrent: false)
        let windows = [window("B", app: "Beta", space: current), window("A", app: "Alpha", space: other),
                       window("C", app: "Gamma", space: current)]
        func selected(allSpaces: Bool, focusedID: String?, reverse: Bool = false) -> String {
            let start = WindowSwitcher.start(windows, allSpaces: allSpaces, focusedID: focusedID, reverse: reverse)
            return start.results[start.selectedIndex].window.id
        }
        XCTAssertEqual(selected(allSpaces: false, focusedID: "B"), "C")
        XCTAssertEqual(selected(allSpaces: false, focusedID: nil), "B")
        XCTAssertEqual(selected(allSpaces: true, focusedID: "B", reverse: true), "A")
        XCTAssertEqual(selected(allSpaces: true, focusedID: "C"), "B")
        let single = WindowSwitcher.start([window("B", app: "Beta", space: current)], allSpaces: true,
                                          focusedID: "B", reverse: false)
        XCTAssertEqual(single.selectedIndex, 0)
        XCTAssertTrue(WindowSwitcher.start([], allSpaces: true, focusedID: nil, reverse: false).results.isEmpty)
    }

    func testUnknownDesktopRemainsAvailableWhenTopologyIsUnavailable() {
        let windows = [window("fallback", app: "Editor", space: nil)]
        XCTAssertEqual(WindowSwitcher.filter(windows, query: "", allSpaces: false).map(\.window.id), ["fallback"])
    }
}
