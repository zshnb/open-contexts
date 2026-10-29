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

    func testUnknownDesktopRemainsAvailableWhenTopologyIsUnavailable() {
        let windows = [window("fallback", app: "Editor", space: nil)]
        XCTAssertEqual(WindowSwitcher.filter(windows, query: "", allSpaces: false).map(\.window.id), ["fallback"])
    }

    func testCurrentDisplayKeepsItsDesktopsAndWindowsOnUnknownDisplays() {
        let main = WindowSpace(id: 1, index: 1, isCurrent: true, displayID: "MAIN")
        let mainOther = WindowSpace(id: 2, index: 2, isCurrent: false, displayID: "MAIN")
        let side = WindowSpace(id: 3, index: 3, isCurrent: true, displayID: "SIDE")
        let shared = WindowSpace(id: 4, index: 4, isCurrent: true, displayID: "Main")
        let windows = [window("main", app: "Editor", space: main),
                       window("main-other", app: "Editor", space: mainOther),
                       window("side", app: "Chat", space: side),
                       window("shared", app: "Mail", space: shared),
                       window("unknown", app: "Notes", space: nil)]
        XCTAssertEqual(WindowSwitcher.windows(windows, onDisplay: "MAIN", knownDisplays: ["MAIN", "SIDE"]).map(\.id),
                       ["main", "main-other", "shared", "unknown"])
        XCTAssertEqual(WindowSwitcher.windows(windows, onDisplay: "SIDE", knownDisplays: ["MAIN", "SIDE"]).map(\.id),
                       ["side", "shared", "unknown"])
    }
}
