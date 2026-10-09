import Foundation
import XCTest
@testable import OpenContextsCore

final class GroupStoreTests: XCTestCase {
    func testFocusRecencyDoesNotReorderLiveOrSavedWindows() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        let a = window("a", title: "A")
        let b = window("b", title: "B")
        let c = window("c", title: "C")
        store.updateLiveWindows([a, b, c])
        let revision = store.revision
        let renamed = window("b", title: "Renamed", documentURL: "file:///b")
        store.updateLiveWindows([renamed, a, c])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID)[1], renamed)
        XCTAssertEqual(store.revision, revision)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        let d = window("d", title: "D")
        store.updateLiveWindows([d, c, renamed, a])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b", "c", "d"])
        store.updateLiveWindows([d, c, a])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "c", "d"])

        let changedC = window("c", title: "Changed C")
        store.reconcile([d, changedC, a])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "c", "d"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .compactMap { $0["title"] as? String }, ["A", "Changed C", "D"])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "d", to: work)
        store.moveWindow(id: "a", to: work)
        store.moveWindow(id: "a", to: work, before: "d")
        let persisted = try Data(contentsOf: fileURL)
        store.updateLiveWindows([d, changedC, a])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["a", "d"])
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)
    }

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
        let two = window("old-2", title: "Other", documentURL: "file:///two")
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

    func testLaterLiveDuplicateRestoresSavedGroup() throws {
        let liveAmbiguityURL = temporaryFileURL()
        let original = GroupStore(fileURL: liveAmbiguityURL)
        original.reconcile([window("old", title: "Same")])
        original.createGroup(name: "Saved")
        let saved = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old", to: saved)

        let liveAmbiguity = GroupStore(fileURL: liveAmbiguityURL)
        liveAmbiguity.reconcile([window("a", title: "Same"), window("b", title: "Same")])
        XCTAssertEqual(liveAmbiguity.windows(in: saved).map(\.id), ["b"])
        XCTAssertEqual(liveAmbiguity.windows(in: GroupStore.ungroupedID).map(\.id), ["a"])

        let savedAmbiguityURL = temporaryFileURL()
        let duplicates = GroupStore(fileURL: savedAmbiguityURL)
        duplicates.reconcile([window("a", title: "Same"), window("b", title: "Same")])
        duplicates.reconcile([])

        let savedAmbiguity = GroupStore(fileURL: savedAmbiguityURL)
        savedAmbiguity.reconcile([window("new", title: "Same")])
        XCTAssertEqual(savedAmbiguity.windows(in: GroupStore.ungroupedID).map(\.id), ["new"])
        XCTAssertEqual(try persistedWindows(at: savedAmbiguityURL, in: GroupStore.ungroupedID).count, 1)
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
        XCTAssertEqual(ambiguous.windows(in: saved).map(\.id), ["blank-2"])
        XCTAssertEqual(ambiguous.windows(in: GroupStore.ungroupedID).map(\.id), ["blank-1"])
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

    func testLoadPreservesDistinctSameTitleDocumentsUntilLiveScan() throws {
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
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .compactMap { $0["id"] as? String }, ["blank", "title-conflict", "doc-1", "doc-2"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: customID).compactMap { $0["id"] as? String },
                       ["custom-blank", "custom-document"])

        store.reconcile([
            window("live-custom", title: "Changed", documentURL: "file:///custom"),
            window("live-1", title: "Same", documentURL: "file:///one"),
            window("live-2", title: "Same", documentURL: "file:///two")
        ])
        XCTAssertEqual(store.windows(in: customID).map(\.id), ["live-custom"])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["live-1", "live-2"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .compactMap { $0["documentURL"] as? String }, ["file:///one", "file:///two"])
    }

    func testCorruptPersistenceIsReportedAndNeverOverwritten() throws {
        let fileURL = temporaryFileURL()
        let corrupt = Data("not json".utf8)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try corrupt.write(to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        XCTAssertNotNil(store.persistenceError)
        XCTAssertEqual(store.persistenceErrorOperation, .read)
        XCTAssertFalse(store.persistenceErrorDetail?.isEmpty ?? true)
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

    func testUniquePinnedWindowRebindsAfterDynamicTitleChange() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("pinned", title: "Inbox — 11")
        pinned["pinnedPosition"] = 0
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [
                GroupStore.ungroupedID: [savedWindow("history", title: "Inbox — 12")],
                "work": [pinned]
            ]
        ], to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("live", title: "Inbox — 12")])
        XCTAssertEqual(store.windows(in: "work").map(\.id), ["live"])
        XCTAssertTrue(store.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertTrue(store.isPinned(id: "live"))
        XCTAssertEqual(try persistedWindows(at: fileURL, in: "work").first?["title"] as? String,
                       "Inbox — 12")
    }

    func testLiveRefreshRebindsUniquePinnedWindowWithoutDiskWrite() throws {
        let fileURL = temporaryFileURL()
        let original = GroupStore(fileURL: fileURL)
        original.reconcile([window("old", title: "All iCloud — 12 notes")])
        original.createGroup(name: "Notes")
        let notes = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old", to: notes)
        original.togglePin(id: "old")
        let persisted = try Data(contentsOf: fileURL)

        original.updateLiveWindows([window("new", title: "All iCloud — 10 notes")])
        XCTAssertEqual(original.windows(in: notes).map(\.id), ["new"])
        XCTAssertTrue(original.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertTrue(original.isPinned(id: "new"))
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)

        let restarted = GroupStore(fileURL: fileURL)
        restarted.updateLiveWindows([window("new", title: "All iCloud — 10 notes")])
        XCTAssertEqual(restarted.windows(in: notes).map(\.id), ["new"])
        XCTAssertTrue(restarted.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertTrue(restarted.isPinned(id: "new"))
        XCTAssertEqual(restarted.revision, 0)
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)
    }

    func testPinnedFallbackRejectsAmbiguousLiveApps() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("pinned", title: "Inbox — 10", documentURL: "file:///one")
        pinned["pinnedPosition"] = 0
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [GroupStore.ungroupedID: [], "work": [pinned]]
        ], to: fileURL)

        let ambiguous = GroupStore(fileURL: fileURL)
        ambiguous.updateLiveWindows([window("a", title: "Inbox — 11"),
                                     window("b", title: "Inbox — 12")])
        XCTAssertTrue(ambiguous.windows(in: "work").isEmpty)
        XCTAssertEqual(ambiguous.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b"])

        let differentApp = GroupStore(fileURL: fileURL)
        differentApp.reconcile([window("same-app-name", appID: "com.example.Other",
                                       title: "Inbox — 11")])
        XCTAssertTrue(differentApp.windows(in: "work").isEmpty)
        XCTAssertEqual(differentApp.windows(in: GroupStore.ungroupedID).map(\.id),
                       ["same-app-name"])
    }

    func testUniquePinnedFallbackWinsOverUngroupedExactURL() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("pin", title: "Old page", documentURL: "file:///old")
        pinned["pinnedPosition"] = 0
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [
                GroupStore.ungroupedID: [savedWindow("history", title: "Bitwarden",
                                                      documentURL: "file:///bitwarden")],
                "work": [pinned]
            ]
        ], to: fileURL)

        let multiLive = GroupStore(fileURL: fileURL)
        multiLive.updateLiveWindows([window("old", title: "Old page", documentURL: "file:///old"),
                                     window("bitwarden", title: "Bitwarden",
                                            documentURL: "file:///bitwarden")])
        XCTAssertEqual(multiLive.windows(in: "work").map(\.id), ["old"])
        XCTAssertEqual(multiLive.windows(in: GroupStore.ungroupedID).map(\.id), ["bitwarden"])

        let singleRefresh = GroupStore(fileURL: fileURL)
        singleRefresh.updateLiveWindows([window("bitwarden", title: "Bitwarden",
                                                documentURL: "file:///bitwarden")])
        XCTAssertEqual(singleRefresh.windows(in: "work").map(\.id), ["bitwarden"])

        let singleLive = GroupStore(fileURL: fileURL)
        singleLive.reconcile([window("bitwarden", title: "Bitwarden",
                                     documentURL: "file:///bitwarden")])
        XCTAssertEqual(singleLive.windows(in: "work").map(\.id), ["bitwarden"])
        XCTAssertTrue(singleLive.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertTrue(singleLive.isPinned(id: "bitwarden"))
    }

    func testUniquePinnedWindowRebindsAfterTitleAndDocumentChange() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("pinned", title: "Old title", documentURL: "file:///old")
        pinned["pinnedPosition"] = 0
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [GroupStore.ungroupedID: [], "work": [pinned]]
        ], to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        let persisted = try Data(contentsOf: fileURL)
        let live = window("new", title: "New title", documentURL: "file:///new")
        store.updateLiveWindows([live])
        XCTAssertEqual(store.windows(in: "work").map(\.id), ["new"])
        XCTAssertTrue(store.isPinned(id: "new"))
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([live])
        XCTAssertEqual(restarted.windows(in: "work").map(\.id), ["new"])
        XCTAssertTrue(restarted.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: "work").first?["documentURL"] as? String,
                       "file:///new")
    }

    func testPinnedFallbackRejectsAmbiguousSavedWindows() throws {
        let fileURL = temporaryFileURL()
        var first = savedWindow("first", title: "First", documentURL: "file:///first")
        first["pinnedPosition"] = 0
        var second = savedWindow("second", title: "Second", documentURL: "file:///second")
        second["pinnedPosition"] = 1
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [GroupStore.ungroupedID: [], "work": [first, second]]
        ], to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("live", title: "Third", documentURL: "file:///third")])
        XCTAssertTrue(store.windows(in: "work").isEmpty)
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["live"])
        XCTAssertFalse(store.isPinned(id: "live"))
    }

    func testUniqueAppPinnedFallbackIgnoresTitleChange() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("pinned", title: "Channel 1")
        pinned["pinnedPosition"] = 0
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [GroupStore.ungroupedID: [], "work": [pinned]]
        ], to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("new", title: "Other channel 2")])
        XCTAssertEqual(store.windows(in: "work").map(\.id), ["new"])
        XCTAssertTrue(store.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertTrue(store.isPinned(id: "new"))
    }

    func testPinnedFallbackDoesNotOverwriteExistingUngroupedBinding() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("pinned", title: "Inbox — 10")
        pinned["pinnedPosition"] = 0
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"],
                       ["id": "work", "name": "Work"]],
            "windowsByGroup": [
                GroupStore.ungroupedID: [savedWindow("other", title: "Other")],
                "work": [pinned]
            ]
        ], to: fileURL)

        let store = GroupStore(fileURL: fileURL)
        store.updateLiveWindows([window("live", title: "Other"),
                                 window("second", title: "Temporary")])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["live", "second"])
        store.updateLiveWindows([window("live", title: "Inbox — 11"),
                                 window("different-app", appID: "com.example.Other", title: "Other")])
        XCTAssertTrue(store.windows(in: "work").isEmpty)
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["live", "different-app"])
    }

    func testTwoGroupedLiveWindowsKeepBindingsWhenTitlesCollide() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("a", title: "Before"), window("b", title: "After")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "a", to: work)
        store.moveWindow(id: "b", to: work)
        store.togglePin(id: "a")

        store.reconcile([window("a", title: "After"), window("b", title: "After")])
        XCTAssertEqual(Set(store.windows(in: work).map(\.id)), Set(["a", "b"]))
        XCTAssertTrue(store.windows(in: GroupStore.ungroupedID).isEmpty)
        XCTAssertTrue(store.isPinned(id: "a"))
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 2)
    }

    func testSameTitleDocumentsRestoreSeparatelyAndClosedHistoryIsDeduplicated() throws {
        let fileURL = temporaryFileURL()
        let original = GroupStore(fileURL: fileURL)
        original.reconcile([window("old-a", title: "Same", documentURL: "file:///a"),
                            window("old-b", title: "Same", documentURL: "file:///b")])
        original.createGroup(name: "Work")
        let work = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old-a", to: work)
        original.moveWindow(id: "old-b", to: work)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 2)

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([window("new-b", title: "Same", documentURL: "file:///b"),
                             window("new-a", title: "Same", documentURL: "file:///a")])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["new-a", "new-b"])
        XCTAssertTrue(restarted.windows(in: GroupStore.ungroupedID).isEmpty)

        restarted.reconcile([window("new-a", title: "Same", documentURL: "file:///a")])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["new-a"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 1)
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

    func testLiveRefreshRebindsNewIDsWithoutChangingPersistence() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("old-a", title: "A"), window("old-b", title: "B")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "old-a", to: work)
        store.moveWindow(id: "old-b", to: work)
        let persisted = try Data(contentsOf: fileURL)
        let revision = store.revision

        store.updateLiveWindows([])
        XCTAssertTrue(store.windows(in: work).isEmpty)
        store.updateLiveWindows([window("new-b", title: "B"), window("new-a", title: "A")])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["new-a", "new-b"])
        XCTAssertEqual(store.revision, revision)
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)

        store.updateLiveWindows([window("old-a", title: "Changed"), window("new-a", title: "A"),
                                 window("new-b", title: "B")])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["new-a", "new-b"])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["old-a"])
    }

    func testEmptyInitialReconcileCanRestoreOnLiveRefresh() throws {
        let fileURL = temporaryFileURL()
        let original = GroupStore(fileURL: fileURL)
        original.reconcile([window("old", title: "Draft")])
        original.createGroup(name: "Work")
        let work = try XCTUnwrap(original.groups.last?.id)
        original.moveWindow(id: "old", to: work)

        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile([])
        let persisted = try Data(contentsOf: fileURL)
        let revision = restarted.revision
        restarted.updateLiveWindows([window("new", title: "Draft")])
        XCTAssertEqual(restarted.windows(in: work).map(\.id), ["new"])
        XCTAssertEqual(restarted.revision, revision)
        XCTAssertEqual(try Data(contentsOf: fileURL), persisted)
    }

    func testSameTitleRecordsWithDifferentURLsArePreservedAndAmbiguousTitlesStayUngrouped() throws {
        let fileURL = temporaryFileURL()
        try writeState([
            "groups": [
                ["id": GroupStore.ungroupedID, "name": "未分组"],
                ["id": "work", "name": "Work"],
                ["id": "other", "name": "Other"]
            ],
            "windowsByGroup": [
                GroupStore.ungroupedID: [],
                "work": [savedWindow("work-1", title: "Same", documentURL: "file:///old"),
                         savedWindow("work-2", title: "Same", documentURL: "file:///new")],
                "other": []
            ]
        ], to: fileURL)

        let restarted = GroupStore(fileURL: fileURL)
        XCTAssertNil(restarted.persistenceError)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: "work").compactMap { $0["id"] as? String },
                       ["work-1", "work-2"])
        restarted.reconcile([window("a", title: "Same"), window("b", title: "Same")])
        XCTAssertTrue(restarted.windows(in: "work").isEmpty)
        XCTAssertEqual(restarted.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: "work").count, 1)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID).count, 2)

        let crossGroupURL = temporaryFileURL()
        try writeState([
            "groups": [
                ["id": GroupStore.ungroupedID, "name": "未分组"],
                ["id": "work", "name": "Work"],
                ["id": "other", "name": "Other"]
            ],
            "windowsByGroup": [
                GroupStore.ungroupedID: [],
                "work": [savedWindow("work-1", title: "Same", documentURL: "file:///one")],
                "other": [savedWindow("other-1", title: "Same", documentURL: "file:///two")]
            ]
        ], to: crossGroupURL)
        let ambiguous = GroupStore(fileURL: crossGroupURL)
        ambiguous.updateLiveWindows([window("live", title: "Same")])
        XCTAssertTrue(ambiguous.windows(in: "work").isEmpty)
        XCTAssertTrue(ambiguous.windows(in: "other").isEmpty)
        XCTAssertEqual(ambiguous.windows(in: GroupStore.ungroupedID).map(\.id), ["live"])
        ambiguous.updateLiveWindows([window("one", title: "Same", documentURL: "file:///one"),
                                     window("two", title: "Same", documentURL: "file:///two")])
        XCTAssertEqual(ambiguous.windows(in: "work").map(\.id), ["one"])
        XCTAssertEqual(ambiguous.windows(in: "other").map(\.id), ["two"])
    }

    func testMovingSameTitleKeepsBothActiveBindings() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("old", title: "Draft", documentURL: "file:///old"),
                         window("blocker", title: "Other"),
                         window("new", title: "Draft", documentURL: "file:///new")])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .compactMap { $0["documentURL"] as? String }, ["file:///old", "file:///new"])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "old", to: work)
        store.moveWindow(id: "blocker", to: work)
        store.moveWindow(id: "new", to: work, before: "old")

        XCTAssertEqual(store.windows(in: work).map(\.id), ["new", "old", "blocker"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).compactMap { $0["documentURL"] as? String },
                       ["file:///new", "file:///old"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 3)
        store.moveWindow(id: "old", to: GroupStore.ungroupedID)
        XCTAssertEqual(store.windows(in: work).map(\.id), ["new", "blocker"])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["old"])

        let reloaded = GroupStore(fileURL: fileURL)
        XCTAssertNil(reloaded.persistenceError)
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 2)
    }

    func testTitleCollisionKeepsBothLiveWindowsBound() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("old", title: "Before"), window("new", title: "After")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "old", to: work)
        store.moveWindow(id: "new", to: work)

        store.reconcile([window("old", title: "After"), window("new", title: "After")])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["old", "new"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).count, 2)
        store.moveWindow(id: "old", to: GroupStore.ungroupedID)
        XCTAssertEqual(store.windows(in: work).map(\.id), ["new"])
    }

    func testPinPersistsAcrossRestartAndCanBeRemoved() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("a", title: "A"), window("b", title: "B")])
        XCTAssertFalse(store.isPinned(id: "b"))
        store.togglePin(id: "b")
        XCTAssertTrue(store.isPinned(id: "b"))
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)[1]["pinnedPosition"] as? Int,
                       1)

        let restarted = GroupStore(fileURL: fileURL)
        XCTAssertNil(restarted.persistenceError)
        restarted.reconcile([window("new-a", title: "A"), window("new-b", title: "B")])
        XCTAssertTrue(restarted.isPinned(id: "new-b"))
        restarted.togglePin(id: "new-b")
        XCTAssertFalse(restarted.isPinned(id: "new-b"))
        XCTAssertNil(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)[1]["pinnedPosition"])
    }

    func testInvalidPinnedPositionBlocksPersistence() throws {
        let fileURL = temporaryFileURL()
        var invalid = savedWindow("bad", title: "Bad")
        invalid["pinnedPosition"] = -1
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"]],
            "windowsByGroup": [GroupStore.ungroupedID: [invalid]]
        ], to: fileURL)
        let original = try Data(contentsOf: fileURL)
        let store = GroupStore(fileURL: fileURL)
        XCTAssertNotNil(store.persistenceError)
        store.createGroup(name: "Must not overwrite")
        XCTAssertEqual(try Data(contentsOf: fileURL), original)
    }

    func testPinningUnsavedLiveWindowKeepsVisiblePosition() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.updateLiveWindows([window("a", title: "A"), window("b", title: "B"),
                                 window("c", title: "C")])
        store.togglePin(id: "b")
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .compactMap { $0["title"] as? String }, ["A", "B"])
        XCTAssertTrue(store.isPinned(id: "b"))
    }

    func testPinnedVisibleSlotSurvivesClosingAndRestoringNeighbors() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        let all = [window("a", title: "A"), window("b", title: "B"),
                   window("c", title: "C"), window("d", title: "D")]
        store.reconcile(all)
        store.togglePin(id: "b")
        store.updateLiveWindows(Array(all.dropFirst()))
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["c", "b", "d"])
        store.updateLiveWindows([all[1], all[3]])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["d", "b"])
        store.updateLiveWindows(all.reversed())
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b", "c", "d"])

        store.moveWindow(id: "b", to: GroupStore.ungroupedID)
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "c", "d", "b"])
        XCTAssertEqual(try persistedWindows(at: fileURL, in: GroupStore.ungroupedID)
            .last?["pinnedPosition"] as? Int, 3)
    }

    func testMultiplePinnedWindowsKeepDistinctVisibleSlots() throws {
        let store = GroupStore(fileURL: temporaryFileURL())
        let all = [window("a", title: "A"), window("b", title: "B"),
                   window("c", title: "C"), window("d", title: "D")]
        store.reconcile(all)
        store.togglePin(id: "b")
        store.togglePin(id: "d")
        store.updateLiveWindows(Array(all.dropFirst()))
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["c", "b", "d"])
        store.updateLiveWindows(all)
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b", "c", "d"])
    }

    func testManualDropCanPlaceNotesImmediatelyAfterPinnedMail() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        let all = [window("mail", title: "Mail"), window("other", title: "Other"),
                   window("notes", title: "Notes")]
        store.reconcile(all)
        store.togglePin(id: "mail")
        store.togglePin(id: "other")
        let preview = ["mail", "notes", "other"]
        store.moveWindow(id: "notes", to: GroupStore.ungroupedID, before: "other",
                         visibleOrderByGroup: [GroupStore.ungroupedID: preview])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), preview)
        XCTAssertEqual(store.pinPosition(id: "mail"), 0)
        XCTAssertEqual(store.pinPosition(id: "other"), 2)
        store.moveWindow(id: "notes", to: GroupStore.ungroupedID)
        store.moveWindow(id: "notes", to: GroupStore.ungroupedID, before: "other")
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), preview)
        XCTAssertEqual(store.pinPosition(id: "other"), 2)
        store.updateLiveWindows(Array(all.prefix(2)))
        XCTAssertEqual(store.pinPosition(id: "other"), 2)
        store.updateLiveWindows(all.reversed())
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), preview)
        let restarted = GroupStore(fileURL: fileURL)
        restarted.reconcile(all.reversed())
        XCTAssertEqual(restarted.windows(in: GroupStore.ungroupedID).map(\.id), preview)
        XCTAssertTrue(restarted.isPinned(id: "mail"))
        XCTAssertTrue(restarted.isPinned(id: "other"))
    }

    func testDraggingPinnedWindowShiftsOtherPinsToMatchManualOrder() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "C"), window("d", title: "D")])
        store.togglePin(id: "b")
        store.togglePin(id: "d")
        store.moveWindow(id: "d", to: GroupStore.ungroupedID, before: "b")
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "d", "b", "c"])
        XCTAssertEqual(store.pinPosition(id: "b"), 2)
        XCTAssertEqual(store.pinPosition(id: "d"), 1)

        store.createGroup(name: "Other")
        let other = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "a", to: other)
        store.togglePin(id: "a")
        store.moveWindow(id: "d", to: other, before: "a")
        XCTAssertEqual(store.windows(in: other).map(\.id), ["d", "a"])
        XCTAssertEqual(store.pinPosition(id: "a"), 1)
        XCTAssertEqual(store.pinPosition(id: "d"), 0)
    }

    func testTitleCollisionKeepsAbsolutePinSlotForLaterGrowth() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "C"), window("d", title: "D")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        for id in ["a", "b", "c", "d"] { store.moveWindow(id: id, to: work) }
        store.togglePin(id: "d")
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "B"), window("d", title: "D")])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(store.pinPosition(id: "d"), 3)
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "B"), window("d", title: "D"),
                         window("e", title: "E")])
        store.moveWindow(id: "e", to: work)
        XCTAssertEqual(store.windows(in: work).map(\.id), ["a", "b", "c", "d", "e"])
        XCTAssertEqual(store.pinPosition(id: "d"), 3)
    }

    func testDropPreservesPreviewOrderWhenSavedAndVisibleOrderDiffer() throws {
        let fileURL = temporaryFileURL()
        var pinned = savedWindow("saved-b", title: "B")
        pinned["pinnedPosition"] = 3
        try writeState([
            "groups": [["id": GroupStore.ungroupedID, "name": "未分组"]],
            "windowsByGroup": [GroupStore.ungroupedID: [
                savedWindow("saved-a", title: "A"), pinned,
                savedWindow("saved-c", title: "C"), savedWindow("saved-d", title: "D")
            ]]
        ], to: fileURL)
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "C"), window("d", title: "D")])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "c", "d", "b"])
        let preview = ["a", "d", "c", "b"]
        store.moveWindow(id: "c", to: GroupStore.ungroupedID, before: "b",
                         visibleOrderByGroup: [GroupStore.ungroupedID: preview])
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), preview)
        XCTAssertEqual(store.pinPosition(id: "b"), 3)
    }

    func testDeletingGroupAppendsItsPinnedWindowsWithoutMovingExistingPin() throws {
        let store = GroupStore(fileURL: temporaryFileURL())
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "C")])
        store.togglePin(id: "b")
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "c", to: work)
        store.togglePin(id: "c")
        store.deleteGroup(id: work)
        XCTAssertEqual(store.windows(in: GroupStore.ungroupedID).map(\.id), ["a", "b", "c"])
        XCTAssertTrue(store.isPinned(id: "b"))
        XCTAssertTrue(store.isPinned(id: "c"))
    }

    func testPinnedSlotStaysWithOriginalWindowAfterTitleCollision() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "C"), window("d", title: "D")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        for id in ["a", "b", "c", "d"] { store.moveWindow(id: id, to: work) }
        store.togglePin(id: "b")

        store.moveWindow(id: "d", to: work, before: "b")
        XCTAssertEqual(store.windows(in: work).map(\.id), ["a", "d", "b", "c"])

        store.reconcile([window("a", title: "A"), window("b", title: "B"),
                         window("c", title: "C"), window("d", title: "B")])
        XCTAssertEqual(store.windows(in: work).map(\.id), ["a", "d", "b", "c"])
        XCTAssertFalse(store.isPinned(id: "d"))
        XCTAssertTrue(store.isPinned(id: "b"))
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work)[2]["pinnedPosition"] as? Int, 2)

        store.moveWindow(id: "d", to: work)
        XCTAssertEqual(store.windows(in: work).map(\.id), ["a", "b", "c", "d"])
        XCTAssertTrue(store.isPinned(id: "d"))
    }

    func testDraggedSameTitleWindowKeepsOriginalPinnedWindow() throws {
        let fileURL = temporaryFileURL()
        let store = GroupStore(fileURL: fileURL)
        store.reconcile([window("old", title: "Same", documentURL: "file:///old"),
                         window("other", title: "Other"),
                         window("new", title: "Same", documentURL: "file:///new")])
        store.createGroup(name: "Work")
        let work = try XCTUnwrap(store.groups.last?.id)
        store.moveWindow(id: "old", to: work)
        store.moveWindow(id: "other", to: work)
        store.togglePin(id: "old")
        store.moveWindow(id: "new", to: work)
        XCTAssertEqual(store.windows(in: work).map(\.id), ["old", "other", "new"])
        XCTAssertTrue(store.isPinned(id: "new"))
        XCTAssertEqual(try persistedWindows(at: fileURL, in: work).last?["pinnedPosition"] as? Int, 2)
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
