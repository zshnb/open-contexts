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

    func testVisibleSpacesKeepOrderAndOnlyDropOtherDesktops() {
        let spaces: [WindowSpace?] = [nil, WindowSpace(id: 1, index: 1, isCurrent: true),
                                      WindowSpace(id: 2, index: 2, isCurrent: false),
                                      WindowSpace(id: 3, index: 3, isCurrent: false, isFullscreen: true)]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let windows = (0..<Int.random(in: 0...12, using: &generator)).map {
                window("w\($0)", app: "App", space: spaces.randomElement(using: &generator)!)
            }
            XCTAssertEqual(windows.onVisibleSpaces(allSpaces: true), windows)
            let current = windows.onVisibleSpaces(allSpaces: false)
            XCTAssertEqual(current, windows.filter { $0.space?.isCurrent != false })
            XCTAssertTrue(current.allSatisfy(\.isOnCurrentSpace))
            XCTAssertEqual(windows.filter { !$0.isOnCurrentSpace }.count + current.count, windows.count)
        }
    }
}
