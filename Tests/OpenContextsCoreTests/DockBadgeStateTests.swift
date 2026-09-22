import Foundation
import XCTest
@testable import OpenContextsCore

final class DockBadgeStateTests: XCTestCase {
    func testMapsApplicationURLAndMergesClearFailureAndSharedAppWindows() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "com.example.shared", "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: appURL) }

        let appID = try XCTUnwrap(DockBadgeState.appID(for: appURL))
        XCTAssertEqual(appID, "com.example.shared")
        let windowAppIDs = [appID, appID]

        var state = DockBadgeState()
        state.merge(activeAppIDs: Set(windowAppIDs), reads: [appID: .value("123")])
        XCTAssertEqual(windowAppIDs.map { state.badges[$0] }, ["99+", "99+"])

        state.merge(activeAppIDs: Set(windowAppIDs), reads: nil)
        XCTAssertEqual(state.badges[appID], "99+")
        state.merge(activeAppIDs: Set(windowAppIDs), reads: [appID: .failure])
        XCTAssertEqual(state.badges[appID], "99+")
        state.merge(activeAppIDs: Set(windowAppIDs), reads: [appID: .value(nil)])
        XCTAssertNil(state.badges[appID])

        state.merge(activeAppIDs: Set(windowAppIDs), reads: [appID: .value("•")])
        XCTAssertEqual(state.badges[appID], "•")
        XCTAssertEqual(DockBadgeState.displayValue("1"), "1")
        XCTAssertEqual(DockBadgeState.displayValue("12"), "12")
        XCTAssertEqual(DockBadgeState.displayValue("100"), "99+")
        XCTAssertEqual(DockBadgeState.displayValue("99+"), "99+")
        XCTAssertEqual(DockBadgeState.displayValue("new"), "•")
        XCTAssertNil(DockBadgeState.displayValue(nil))
        state.merge(activeAppIDs: [], reads: nil)
        XCTAssertTrue(state.badges.isEmpty)
    }
}
