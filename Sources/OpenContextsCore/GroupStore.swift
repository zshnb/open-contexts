import Combine
import Foundation

public struct WindowGroup: Identifiable, Codable, Equatable {
    public let id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public final class GroupStore: ObservableObject {
    public static let ungroupedID = "ungrouped"

    @Published public private(set) var groups: [WindowGroup]
    @Published public private(set) var revision = 0
    public private(set) var persistenceError: String?

    private struct SavedWindow: Codable, Equatable {
        let id: String
        var appID: String
        var title: String
        var documentURL: String?
    }

    private struct State: Codable {
        var groups: [WindowGroup]
        var windowsByGroup: [String: [SavedWindow]]
    }

    private let fileURL: URL
    private var windowsByGroup: [String: [SavedWindow]]
    private var activeWindows: [String: WindowInfo] = [:]
    private var savedIDByWindowID: [String: String] = [:]
    private var persistenceBlocked = false

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.groups = [WindowGroup(id: Self.ungroupedID, name: "未分组")]
        self.windowsByGroup = [Self.ungroupedID: []]
        load()
    }

    public func reconcile(_ windows: [WindowInfo]) {
        var incoming: [String: WindowInfo] = [:]
        var uniqueWindows: [WindowInfo] = []
        for window in windows where incoming[window.id] == nil {
            incoming[window.id] = window
            uniqueWindows.append(window)
        }
        guard incoming != activeWindows else { return }

        savedIDByWindowID = savedIDByWindowID.filter { incoming[$0.key] != nil }

        for (windowID, savedID) in savedIDByWindowID {
            guard let window = incoming[windowID] else { continue }
            updateSavedWindow(id: savedID, from: window)
        }

        let newWindows = uniqueWindows.filter { savedIDByWindowID[$0.id] == nil }
        let liveKeyCounts = Dictionary(grouping: uniqueWindows.flatMap(matchKeys), by: { $0 }).mapValues(\.count)
        let savedWindows = windowsByGroup.values.flatMap { $0 }
        let savedByKey = Dictionary(grouping: savedWindows.flatMap { saved in
            matchKeys(saved).map { ($0, saved) }
        }, by: { $0.0 }).mapValues { $0.map(\.1) }
        var usedSavedIDs = Set(savedIDByWindowID.values)

        for window in newWindows {
            let key = preferredMatchKey(window)
            let match = key.flatMap { key -> SavedWindow? in
                guard liveKeyCounts[key] == 1, savedByKey[key]?.count == 1,
                      let saved = savedByKey[key]?.first, !usedSavedIDs.contains(saved.id) else {
                    return nil
                }
                return saved
            }

            if let match {
                savedIDByWindowID[window.id] = match.id
                usedSavedIDs.insert(match.id)
                updateSavedWindow(id: match.id, from: window)
            } else {
                let saved = SavedWindow(id: UUID().uuidString, appID: window.appID,
                                        title: window.title, documentURL: window.documentURL)
                windowsByGroup[Self.ungroupedID, default: []].append(saved)
                savedIDByWindowID[window.id] = saved.id
                usedSavedIDs.insert(saved.id)
            }
        }

        activeWindows = incoming
        changed()
    }

    public func windows(in groupID: String) -> [WindowInfo] {
        guard groups.contains(where: { $0.id == groupID }) else { return [] }
        let windowIDBySavedID = Dictionary(uniqueKeysWithValues: savedIDByWindowID.map { ($0.value, $0.key) })
        return windowsByGroup[groupID, default: []].compactMap { saved in
            windowIDBySavedID[saved.id].flatMap { activeWindows[$0] }
        }
    }

    public func createGroup(name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = WindowGroup(id: UUID().uuidString, name: name)
        groups.append(group)
        windowsByGroup[group.id] = []
        changed()
    }

    public func renameGroup(id: String, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != Self.ungroupedID, !name.isEmpty,
              let index = groups.firstIndex(where: { $0.id == id }), groups[index].name != name else { return }
        groups[index].name = name
        changed()
    }

    public func deleteGroup(id: String) {
        guard id != Self.ungroupedID,
              let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups.remove(at: index)
        windowsByGroup[Self.ungroupedID, default: []].append(contentsOf: windowsByGroup.removeValue(forKey: id) ?? [])
        changed()
    }

    public func moveWindow(id: String, to groupID: String, before windowID: String? = nil) {
        guard groups.contains(where: { $0.id == groupID }),
              let savedID = savedIDByWindowID[id] else { return }
        let beforeSavedID = windowID.flatMap { savedIDByWindowID[$0] }
        if beforeSavedID == savedID { return }

        var moved: SavedWindow?
        for group in groups {
            guard let index = windowsByGroup[group.id]?.firstIndex(where: { $0.id == savedID }) else { continue }
            moved = windowsByGroup[group.id]?.remove(at: index)
            break
        }
        guard let moved else { return }
        let index = beforeSavedID.flatMap { id in
            windowsByGroup[groupID, default: []].firstIndex(where: { $0.id == id })
        } ?? windowsByGroup[groupID, default: []].endIndex
        windowsByGroup[groupID, default: []].insert(moved, at: index)
        changed()
    }

    public func moveGroup(id: String, before groupID: String?) {
        guard id != Self.ungroupedID,
              let source = groups.firstIndex(where: { $0.id == id }),
              groupID != Self.ungroupedID, groupID != id else { return }
        let group = groups.remove(at: source)
        let destination = groupID.flatMap { target in groups.firstIndex(where: { $0.id == target }) }
            ?? groups.endIndex
        groups.insert(group, at: destination)
        changed()
    }

    private static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenContexts", isDirectory: true)
            .appendingPathComponent("groups.json")
    }

    private func preferredMatchKey(_ window: WindowInfo) -> String? {
        if let documentURL = window.documentURL, !documentURL.isEmpty {
            return "document\u{0}\(window.appID)\u{0}\(documentURL)"
        }
        guard !window.title.isEmpty else { return nil }
        return "title\u{0}\(window.appID)\u{0}\(window.title)"
    }

    private func matchKeys(_ window: WindowInfo) -> [String] {
        var keys = window.title.isEmpty ? [] : ["title\u{0}\(window.appID)\u{0}\(window.title)"]
        if let documentURL = window.documentURL, !documentURL.isEmpty {
            keys.append("document\u{0}\(window.appID)\u{0}\(documentURL)")
        }
        return keys
    }

    private func matchKeys(_ window: SavedWindow) -> [String] {
        var keys = window.title.isEmpty ? [] : ["title\u{0}\(window.appID)\u{0}\(window.title)"]
        if let documentURL = window.documentURL, !documentURL.isEmpty {
            keys.append("document\u{0}\(window.appID)\u{0}\(documentURL)")
        }
        return keys
    }

    private func updateSavedWindow(id: String, from window: WindowInfo) {
        for group in groups {
            guard let index = windowsByGroup[group.id]?.firstIndex(where: { $0.id == id }) else { continue }
            windowsByGroup[group.id]?[index].appID = window.appID
            windowsByGroup[group.id]?[index].title = window.title
            windowsByGroup[group.id]?[index].documentURL = window.documentURL
            return
        }
    }

    private func changed() {
        save()
        revision += 1
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
            let ids = state.groups.map(\.id)
            let savedCount = state.windowsByGroup.values.reduce(0) { $0 + $1.count }
            guard ids.first == Self.ungroupedID, state.groups.first?.name == "未分组",
                  Set(ids).count == ids.count,
                  Set(state.windowsByGroup.keys).isSubset(of: Set(ids)),
                  Set(state.windowsByGroup.values.flatMap { $0.map(\.id) }).count == savedCount else {
                throw CocoaError(.fileReadCorruptFile)
            }
            groups = state.groups
            windowsByGroup = state.windowsByGroup
            for id in ids where windowsByGroup[id] == nil { windowsByGroup[id] = [] }
        } catch {
            persistenceBlocked = true
            persistenceError = "无法读取分组数据：\(error.localizedDescription)"
        }
    }

    private func save() {
        guard !persistenceBlocked else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(State(groups: groups, windowsByGroup: windowsByGroup))
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "无法保存分组数据：\(error.localizedDescription)"
        }
    }
}
