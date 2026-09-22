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

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("groups.json")
    }

    private func window(_ id: String, appID: String = "com.example.Editor",
                        title: String, documentURL: String? = nil) -> WindowInfo {
        WindowInfo(id: id, appID: appID, appName: "Editor",
                   title: title, documentURL: documentURL, processID: 1)
    }
}
