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

    func testPinyinMatchesChineseAppNamesAndTitles() throws {
        let wechat = window("1", app: "微信", title: "文件传输助手")
        let full = try XCTUnwrap(WindowSearch.match(wechat, query: "WeiXin"))
        XCTAssertEqual(full.appRanges, [NSRange(location: 0, length: 2)])
        XCTAssertTrue(full.titleRanges.isEmpty)
        XCTAssertEqual(try XCTUnwrap(WindowSearch.match(wechat, query: "weix")).appRanges,
                       [NSRange(location: 0, length: 2)])
        XCTAssertEqual(try XCTUnwrap(WindowSearch.match(wechat, query: "xin")).appRanges,
                       [NSRange(location: 1, length: 1)])
        let title = try XCTUnwrap(WindowSearch.match(wechat, query: "weixin chuanshu"))
        XCTAssertEqual(title.titleRanges, [NSRange(location: 2, length: 2)])

        let music = window("2", app: "QQ音乐", title: "")
        XCTAssertEqual(try XCTUnwrap(WindowSearch.match(music, query: "qqyinle")).appRanges,
                       [NSRange(location: 0, length: 4)])
    }

    func testPinyinStartsAtACharacterAndRanksBelowLiteralMatches() {
        let windows = [window("pinyin", app: "微信", title: ""),
                       window("literal", app: "Weixin", title: "")]
        XCTAssertEqual(WindowSearch.filter(windows, query: "weixin").map(\.window.id), ["literal", "pinyin"])
        XCTAssertEqual(WindowSearch.filter(windows, query: "weix").map(\.window.id), ["literal", "pinyin"])
        XCTAssertEqual(WindowSearch.filter(windows.reversed(), query: "weix").map(\.window.id), ["literal", "pinyin"])
        XCTAssertNil(WindowSearch.match(window("3", app: "微信", title: ""), query: "eixin"))
        XCTAssertNil(WindowSearch.match(window("4", app: "微信", title: ""), query: "wx"))
        XCTAssertNil(WindowSearch.match(window("5", app: "微 信", title: ""), query: "weixin"))
    }

    func testNoResultsAndNoTypoCorrection() {
        let windows = [window("1", app: "Chrome", title: "GitHub")]
        XCTAssertTrue(WindowSearch.filter(windows, query: "zzzz").isEmpty)
        XCTAssertTrue(WindowSearch.filter(windows, query: "chorme").isEmpty)
    }
}
