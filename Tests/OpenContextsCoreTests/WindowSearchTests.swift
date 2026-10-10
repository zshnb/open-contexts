import XCTest
@testable import OpenContextsCore

final class WindowSearchTests: XCTestCase {
    private func window(_ id: String, app: String, title: String) -> WindowInfo {
        WindowInfo(id: id, appID: app, appName: app, title: title, processID: 1)
    }

    func testEmptyQueryPreservesRecentOrder() {
        let windows = [window("1", app: "Warp", title: "Terminal"),
                       window("2", app: "Chrome", title: "GitHub")]
        XCTAssertEqual(WindowSearch.filter(windows, query: " \t ").map(\.window), windows)
        XCTAssertTrue(WindowSearch.filter(windows, query: " \t ").allSatisfy {
            $0.appRanges.isEmpty && $0.titleRanges.isEmpty
        })
    }

    func testFilterCarriesHighlightsWithTheirWindowAfterRanking() {
        let windows = [window("title", app: "Editor", title: "Reopen project"),
                       window("missing", app: "Chrome", title: "Notes"),
                       window("app", app: "OpenContexts", title: "Settings")]
        let matches = WindowSearch.filter(windows, query: "  OPEN  ")
        XCTAssertEqual(matches.map(\.window.id), ["app", "title"])
        XCTAssertEqual(matches[0].appRanges, [NSRange(location: 0, length: 4)])
        XCTAssertTrue(matches[0].titleRanges.isEmpty)
        XCTAssertTrue(matches[1].appRanges.isEmpty)
        XCTAssertEqual(matches[1].titleRanges, [NSRange(location: 2, length: 4)])
    }

    func testEachTokenCanMatchEitherAppOrTitle() throws {
        let target = window("1", app: "Google Chrome", title: "OpenContexts — GitHub")
        let match = try XCTUnwrap(WindowSearch.match(target, query: "CHR context"))
        XCTAssertEqual(match.appRanges, [NSRange(location: 7, length: 3)])
        XCTAssertEqual(match.titleRanges, [NSRange(location: 4, length: 7)])
        XCTAssertNil(WindowSearch.match(target, query: "chr missing"))
    }

    func testExactPrefixAndWordStartMatchesRankAheadOfInternalMatches() {
        let windows = [window("internal", app: "mychrome", title: ""),
                       window("contains", app: "My Chrome", title: ""),
                       window("prefix", app: "Chrome Beta", title: ""),
                       window("exact", app: "Chrome", title: "")]
        XCTAssertEqual(WindowSearch.filter(windows, query: "chrome").map(\.window.id),
                       ["exact", "prefix", "contains", "internal"])
    }

    func testRejectsAcronymsAndNonConsecutiveCharacters() {
        let code = window("1", app: "Visual Studio Code", title: "")
        XCTAssertNil(WindowSearch.match(code, query: "vsc"))
        XCTAssertNil(WindowSearch.match(window("2", app: "OpenContexts", title: ""), query: "oc"))
        XCTAssertNil(WindowSearch.match(code, query: "csv"))
    }

    func testOpenMatchesOnlyContiguousTextInAppOrTitle() throws {
        let windows = [window("scattered-app", app: "Outlook Preview Editor Notes", title: ""),
                       window("scattered-title", app: "Editor", title: "o p e n"),
                       window("app", app: "OpenContexts", title: ""),
                       window("title", app: "Editor", title: "ReOPEN project")]
        XCTAssertEqual(WindowSearch.filter(windows, query: "open").map(\.window.id), ["app", "title"])
        let appMatch = try XCTUnwrap(WindowSearch.match(windows[2], query: "open"))
        XCTAssertEqual(appMatch.appRanges, [NSRange(location: 0, length: 4)])
        let titleMatch = try XCTUnwrap(WindowSearch.match(windows[3], query: "open"))
        XCTAssertEqual(titleMatch.titleRanges, [NSRange(location: 2, length: 4)])
        XCTAssertNil(WindowSearch.match(window("split", app: "Op", title: "en"), query: "open"))
    }

    func testEqualScoresPreserveRecentOrder() {
        let windows = [window("recent", app: "Chrome", title: "GitHub"),
                       window("older", app: "Chrome", title: "Docs")]
        XCTAssertEqual(WindowSearch.filter(windows, query: "chr").map(\.window), windows)
    }

    func testUnicodeTitlesUseUTF16RangesForHighlighting() throws {
        let target = window("1", app: "Editor", title: "🧑‍💻 Café — OpenContexts")
        let match = try XCTUnwrap(WindowSearch.match(target, query: "cafe open"))
        let title = target.displayTitle as NSString
        XCTAssertEqual(match.titleRanges.map { title.substring(with: $0) }, ["Café", "Open"])
    }

    func testNoResultsAndNoTypoCorrection() {
        let windows = [window("1", app: "Chrome", title: "GitHub")]
        XCTAssertTrue(WindowSearch.filter(windows, query: "zzzz").isEmpty)
        XCTAssertTrue(WindowSearch.filter(windows, query: "chorme").isEmpty)
    }
}
