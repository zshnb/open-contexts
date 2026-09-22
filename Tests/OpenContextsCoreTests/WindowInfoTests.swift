import XCTest
@testable import OpenContextsCore

final class WindowInfoTests: XCTestCase {
    func testDisplayTitleTrimsAndFallsBackWithoutChangingRawTitle() {
        var window = WindowInfo(id: "1", appID: "com.example.app", appName: "NetEase Music",
                                title: "  Playlist \n", processID: 1)
        XCTAssertEqual(window.displayTitle, "Playlist")
        XCTAssertEqual(window.title, "  Playlist \n")

        window.title = " \t\n "
        XCTAssertEqual(window.displayTitle, "NetEase Music")
        XCTAssertEqual(window.title, " \t\n ")
    }
}
