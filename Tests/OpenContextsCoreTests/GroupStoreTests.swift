import Foundation
import XCTest
@testable import OpenContextsCore

final class GroupStoreTests: XCTestCase {
    func testGroupAndWindowOrderingAndDeletion() throws {
        let store = GroupStore(fileURL: temporaryFileURL())
        let windows = [window("1", title: "One"), window("2", title: "Two"), window("3", title: "Three")]
        store.reconcile(windows)
        store.createGroup(name: " Work ")
        store.createGroup(name: "Later")
        let work = try XCTUnwrap(store.groups.first(where: { $0.name == "Work" })?.id)
        let later = try XCTUnwrap(store.groups.first(where: { $0.name == "Later" })?.id)

        store.moveWindow(id: "2", to: work)
        store.moveWindow(id: "1", to: work, before: "2")
        XCTAssertEqual(store.windows(in: work).map(\.id), ["1", "2"])

        store.renameGroup(id: work, name: "Focus")
        store.renameGroup(id: GroupStore.ungroupedID, name: "Nope")
        store.moveGroup(id: later, before: work)
        XCTAssertEqual(store.groups.map(\.name), ["未分组", "Later", "Focus"])

        store.deleteGroup(id: work)
        XCTAssertEqual(store.groups.map(\.name), ["未分组", "Later"])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["3", "1", "2"])
    }

    func testRestartRestoresDocumentWindowsAndKeepsClosedPosition() throws {
        let fileURL = temporaryFileURL()
        let first = GroupStore(fileURL: fileURL)
        let one = window("old-1", title: "Draft", documentURL: "file:///one")
        let two = window("old-2", title: "Draft", documentURL: "file:///two")
        first.reconcile([one, two])
        first.createGroup(name: "Docs")
        let docs = try XCTUnwrap(first.groups.last?.id)
        first.moveWindow(id: one.id, to: docs)
        first.moveWindow(id: two.id, to: docs)
        first.reconcile([window("old-1", title: "Renamed", documentURL: "file:///one"), two])
        XCTAssertEqual(first.windows(in: docs).map(\.id), ["old-1", "old-2"])
        first.reconcile([two])

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([
            window("new-2", title: "Other", documentURL: "file:///two"),
            window("new-1", title: "Anything", documentURL: "file:///one")
        ])
        XCTAssertEqual(restarted.windows(in: docs).map(\.id), ["new-1", "new-2"])
    }

    func testAmbiguityOnEitherSideFallsBackToUngrouped() throws {
        let liveAmbiguityURL = temporaryFileURL()
        let original = GroupStore(fileURL: liveAmbiguityURL)
        original.reconcile([window("old", title: "Same")])
        original.createGroup(name: "Saved")
        let saved = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old", to: saved)

        let liveAmbiguity = GroupStore(fileURL: liveAmbiguityURL)
        liveAmbiguity.reconcile([window("a", title: "Same"), window("b", title: "Same")])
        XCTAssertTrue(liveAmbiguity.windows(in: saved).isEmpty)
        XCTAssertEqual(Set(liveAmbiguity.windows(in: GroupStore.ungroupedID).map(\.id)), ["a", "b"])

        let savedAmbiguityURL = temporaryFileURL()
        let duplicates = GroupStore(fileURL: savedAmbiguityURL)
        duplicates.reconcile([window("a", title: "Same"), window("b", title: "Same")])
        duplicates.reconcile([])

        let savedAmbiguity = GroupStore(fileURL: savedAmbiguityURL)
        savedAmbiguity.reconcile([window("new", title: "Same")])
        XCTAssertEqual(savedAmbiguity.windows(in: GroupStore.ungroupedID).map(\.id), ["new"])
    }

    func testUntitledWindowSurvivesDesktopSwitchAndRestart() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([
            window("old", appID: "com.netease.163music", title: " \n"),
            window("neighbor", title: "Editor")
        ])
        store.createGroup(name: "Music")
        let music = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "old", to: music)
        store.moveWindow(id: "neighbor", to: music)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: music).count, 2)

        store.reconcile([])
        store.reconcile([
            window("new-neighbor", title: "Editor"),
            window("new", appID: "com.netease.163music", title: "")
        ])
        XCTAssertEqual(store.windows(in: music).map(\.id), ["new", "new-neighbor"])
        store.reconcile([])

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([
            window("restarted-neighbor", title: "Editor"),
            window("restarted", appID: "com.netease.163music", title: "")
        ])
        XCTAssertEqual(restarted.windows(in: music).map(\.id), ["restarted", "restarted-neighbor"])
    }

    func testUntitledFallbackRejectsAmbiguousAndDifferentWindows() throws {
        let fileURL = temporaryFileURL()
        let original = GroupStore(fileURL: fileURL)
        original.reconcile([window("old", title: "")])
        original.createGroup(name: "Saved")
        let saved = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old", to: saved)

        let differentApp = GroupStore(fileURL: fileURL)
        differentApp.reconcile([window("other-app", appID: "com.example.Other", title: "")])
        XCTAssertTrue(differentApp.windows(in: saved).isEmpty)

        let named = GroupStore(fileURL: fileURL)
        named.reconcile([window("named", title: "Named")])
        XCTAssertTrue(named.windows(in: saved).isEmpty)

        let ambiguous = GroupStore(fileURL: fileURL)
        ambiguous.reconcile([window("blank-1", title: ""), window("blank-2", title: "")])
        XCTAssertTrue(ambiguous.windows(in: saved).isEmpty)
        XCTAssertEqual(Set(ambiguous.windows(in: GroupStore.ungroupedID).map(\.id)),
                       ["blank-1", "blank-2"])
    }

    func testUniqueUngroupedWindowSurvivesRepeatedRestartsWithoutGrowth() throws {
        let fileURL = temporaryFileURL()
        for index in 0..<3 {
            let store = GroupStore(fileURL: fileURL)
            let id = "window-\(index)"
            store.reconcile([window(id, title: "Unique")])
            XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), [id])
            store.reconcile([])
            XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID).count, 1)
        }
    }

    func testLoadCleansLegacyJunkWithoutDeletingDistinctDocuments() throws {
        let fileURL = temporaryFileURL()
        let customID = "custom"
        try writeState([
            "groups": [
                ["id": GroupStore.ungroupedID, "name": "未分组"],
                ["id": customID, "name": "Docs"]
            ],
            "windowsByGroup": [
                GroupStore.ungroupedID: [
                    savedWindow("blank", title: ""),
                    savedWindow("title-conflict", title: "Fallback"),
                    savedWindow("doc-1", title: "Same", documentURL: "file:///one"),
                    savedWindow("doc-2", title: "Same", documentURL: "file:///two")
                ],
                customID: [
                    savedWindow("custom-blank", title: ""),
                    savedWindow("custom-document", title: "Fallback", documentURL: "file:///custom")
                ]
            ]
        ], to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        XCTAssertEqual(Set(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .compactMap { $0["id"] as? String }), ["doc-1", "doc-2"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: customID).compactMap { $0["id"] as? String },
                       ["custom-blank", "custom-document"])

        store.reconcile([
            window("live-custom", title: "Changed", documentURL: "file:///custom"),
            window("live-1", title: "Same", documentURL: "file:///one"),
            window("live-2", title: "Same", documentURL: "file:///two")
        ])
        XCTAssertEqual(store.windows(in: customID).map(\.id), ["live-custom"])
        XCTAssertEqual(Set(store.windows(in: GroupStore.ungroupedID).map(\.id)), ["live-1", "live-2"])
    }

    func testCorruptPersistenceIsReportedAndNeverOverwritten() throws {
        let fileURL = temporaryFileURL()
        let corrupt = Data("not json".utf8)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try corrupt.write(to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        XCTAssertNotNil(store.persistenceError)
        store.createGroup(name: "In memory")
        XCTAssertEqual(try Data(contentsOf: fileURL), corrupt)
    }

    func testUnchangedReconcileIsNoOpAndDuplicateIDsCreateOneRecord() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        let first = window("same-id", title: "First")
        store.reconcile([first, window("same-id", title: "Ignored")])
        store.createGroup(name: "Stable")
        let stable = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: first.id, to: stable)

        let revision = store.revision
        let persisted = try Data(contentsOf: fileURL)
        store.reconcile([first])
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)

        store.reconcile([window("same-id", title: "Changed")])
        XCTAssertEqual(store.windows(in: stable).map(\.id), ["same-id"])

        store.reconcile([])
        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([window("new-id", title: "Changed")])
        XCTAssertEqual(restarted.windows(in: stable).map(\.id), ["new-id"])
    }

    func testTitleChangeStaysGroupedAndRestartsByAppAndNewTitle() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("old", title: "Original")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "old", to: work)
        store.reconcile([window("old", title: "Renamed")])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["old"])
        store.reconcile([])

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([
            window("new", title: "Renamed"),
            window("other-app", appID: "com.example.Other", title: "Renamed")
        ])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["new"])
        XCTAssertEqual(restarted.windows(in: GroupStore.ungroupedID).map(\.id), ["other-app"])
    }

    func testLiveRefreshKeepsSavedGroupsUntouchedUntilManualMove() throws {
        let fileURL = temporaryFileURL()
        let original = GroupStore(fileURL: fileURL)
        original.reconcile([window("old", title: "Original")])
        original.createGroup(name: "Work")
        let work = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old", to: work)

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([window("restored", title: "Original")])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["restored"])
        let persisted = try Data(contentsOf: fileURL)
        let revision = restarted.revision

        restarted.updateLiveWindows([window("new", title: "New"), window("restored", title: "Renamed")])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["restored"])
        XCTAssertEqual(restarted.windows(in: work).map(\.title), ["Renamed"])
        XCTAssertEqual(restarted.windows(in: GroupStore.ungroupedID).map(\.id), ["new"])
        restarted.updateLiveWindows([])
        XCTAssertTrue(restarted.windows(in: work).isEmpty)
        XCTAssertTrue(restarted.windows(in: GroupStore.ungroupedID).isEmpty)
        restarted.updateLiveWindows([window("restored", title: "Renamed"), window("new", title: "New")])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["restored"])
        XCTAssertEqual(restarted.revision, revision)
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)

        restarted.moveWindow(id: "restored", to: work)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).first?["title"] as? String, "Renamed")
        restarted.moveWindow(id: "new", to: work)
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["restored", "new"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 2)
        XCTAssertNotEqual(try Data(contentsOf: fileURL), persisted)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("groups.json")
    }

    private func persistedWindows(at fileURL: URL, in groupID: String) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL))
        let root = try XCTUnwrap(object as? [String: Any])
        let windowsByGroup = try XCTUnwrap(root["windowsByGroup"] as? [String: Any])
        return try XCTUnwrap(windowsByGroup[groupID] as? [[String: Any]])
    }

    private func savedWindow(_ id: String, title: String, documentURL: String? = nil) -> [String: Any] {
        ["id": id, "appID": "com.example.Editor", "title": title,
         "documentURL": documentURL ?? NSNull()]
    }

    private func writeState(_ state: [String: Any], to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state).write(to: fileURL)
    }

    private func window(_ id: String, appID: String = "com.example.Editor",
                        title: String, documentURL: String? = nil) -> WindowInfo {
        WindowInfo(id: id, appID: appID, appName: "Editor",
                   title: title, documentURL: documentURL, processID: 1)
    }
}
