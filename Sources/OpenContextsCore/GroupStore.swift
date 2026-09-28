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
        var pinnedPosition: Int? = nil
    }

    private struct State: Codable {
        var groups: [WindowGroup]
        var windowsByGroup: [String: [SavedWindow]]
    }

    private struct WindowKey: Hashable {
        let appID: String
        let title: String
    }

    private let fileURL: URL
    private var windowsByGroup: [String: [SavedWindow]]
    private var activeWindows: [String: WindowInfo] = [:]
    private var activeWindowOrder: [String] = []
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
        activeWindowOrder = activeWindowOrder.filter { incoming[$0] != nil }
        activeWindowOrder.append(contentsOf: uniqueWindows.map(\.id).filter { !activeWindowOrder.contains($0) })

        savedIDByWindowID = savedIDByWindowID.filter { incoming[$0.key] != nil }

        for window in uniqueWindows {
            guard let savedID = savedIDByWindowID[window.id] else { continue }
            updateSavedWindow(id: savedID, from: window)
        }

        let newWindows = activeWindowOrder.compactMap { incoming[$0] }.filter { savedIDByWindowID[$0.id] == nil }
        restoreBindings(for: uniqueWindows)

        for window in newWindows {
            if let savedID = savedIDByWindowID[window.id] {
                updateSavedWindow(id: savedID, from: window)
            } else {
                let saved = SavedWindow(id: UUID().uuidString, appID: window.appID,
                                        title: window.title, documentURL: window.documentURL)
                windowsByGroup[Self.ungroupedID, default: []].append(saved)
                savedIDByWindowID[window.id] = saved.id
            }
        }

        activeWindows = incoming
        changed(preferredSavedIDs: uniqueWindows.compactMap { savedIDByWindowID[$0.id] })
    }

    public func updateLiveWindows(_ windows: [WindowInfo]) {
        var incoming: [String: WindowInfo] = [:]
        var uniqueWindows: [WindowInfo] = []
        for window in windows where incoming[window.id] == nil {
            incoming[window.id] = window
            uniqueWindows.append(window)
        }
        restoreBindings(for: uniqueWindows)
        activeWindows = incoming
        activeWindowOrder = activeWindowOrder.filter { incoming[$0] != nil }
        activeWindowOrder.append(contentsOf: uniqueWindows.map(\.id).filter { !activeWindowOrder.contains($0) })
    }

    public func windows(in groupID: String) -> [WindowInfo] {
        guard groups.contains(where: { $0.id == groupID }) else { return [] }
        let windowIDBySavedID = Dictionary(uniqueKeysWithValues: savedIDByWindowID.map { ($0.value, $0.key) })
        let savedWindows = windowsByGroup[groupID, default: []].compactMap { saved in
            windowIDBySavedID[saved.id].flatMap { activeWindows[$0] }
        }
        let unsavedWindows = groupID == Self.ungroupedID ? activeWindowOrder.compactMap { id in
            savedIDByWindowID[id] == nil ? activeWindows[id] : nil
        } : []
        let visible = savedWindows + unsavedWindows
        let pinned = windowsByGroup[groupID, default: []].compactMap { saved -> (String, Int)? in
            guard let position = saved.pinnedPosition, let liveID = windowIDBySavedID[saved.id] else {
                return nil
            }
            return (liveID, position)
        }
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        return Self.arrangedWindowIDs(visible.map(\.id), pinned: pinned).compactMap { byID[$0] }
    }

    public func pinPosition(id: String) -> Int? {
        guard let savedID = savedIDByWindowID[id] else { return nil }
        return windowsByGroup.values.flatMap { $0 }.first(where: { $0.id == savedID })?.pinnedPosition
    }

    public func reservedPinPositions(in groupID: String) -> Set<Int> {
        Set(windowsByGroup[groupID, default: []].compactMap(\.pinnedPosition))
    }

    public static func availablePinnedPosition(_ requested: Int, occupied: Set<Int>, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var position = min(requested, count - 1)
        while occupied.contains(position) && position < count - 1 { position += 1 }
        while occupied.contains(position) && position > 0 { position -= 1 }
        if occupied.contains(position) {
            position = count
            while occupied.contains(position) { position += 1 }
        }
        return position
    }

    public static func arrangedWindowIDs(_ ids: [String], pinned: [(String, Int)]) -> [String] {
        guard !ids.isEmpty else { return [] }
        var slots = [String?](repeating: nil, count: ids.count)
        var pinnedIDs = Set<String>()
        for (id, requested) in pinned where ids.contains(id) {
            let position = availablePinnedPosition(requested,
                                                   occupied: Set(slots.indices.filter { slots[$0] != nil }),
                                                   count: slots.count)
            slots[position] = id
            pinnedIDs.insert(id)
        }
        let unpinned = ids.filter { !pinnedIDs.contains($0) }
        var next = 0
        for index in slots.indices where slots[index] == nil {
            slots[index] = unpinned[next]
            next += 1
        }
        return slots.compactMap { $0 }
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
        let pinnedSlots = [Self.ungroupedID: pinnedPositions(in: Self.ungroupedID)]
        groups.remove(at: index)
        let offset = windowsByGroup[Self.ungroupedID, default: []].count
        let transferred = (windowsByGroup.removeValue(forKey: id) ?? []).enumerated().map { index, saved in
            var saved = saved
            if saved.pinnedPosition != nil { saved.pinnedPosition = offset + index }
            return saved
        }
        windowsByGroup[Self.ungroupedID, default: []].append(contentsOf: transferred)
        changed(pinnedSlots: pinnedSlots)
    }

    public func isPinned(id: String) -> Bool {
        pinPosition(id: id) != nil
    }

    public func togglePin(id: String) {
        guard let window = activeWindows[id] else { return }
        let groupID = groups.first(where: { group in
            windowsByGroup[group.id, default: []].contains { $0.id == savedIDByWindowID[id] }
        })?.id ?? Self.ungroupedID
        let position = windows(in: groupID).firstIndex(where: { $0.id == id })
        if savedIDByWindowID[id] == nil {
            // Unsaved windows appear after saved ones. Persist the prefix so pinning keeps this row in place.
            for liveID in activeWindowOrder {
                guard savedIDByWindowID[liveID] == nil, let live = activeWindows[liveID] else {
                    if liveID == id { break }
                    continue
                }
                let saved = SavedWindow(id: UUID().uuidString, appID: live.appID,
                                        title: live.title, documentURL: live.documentURL)
                windowsByGroup[Self.ungroupedID, default: []].append(saved)
                savedIDByWindowID[liveID] = saved.id
                if liveID == id { break }
            }
        }
        guard let savedID = savedIDByWindowID[id] else { return }
        updateSavedWindow(id: savedID, from: window)
        let wasPinned = isPinned(id: id)
        for group in groups {
            guard let index = windowsByGroup[group.id]?.firstIndex(where: { $0.id == savedID }) else { continue }
            windowsByGroup[group.id]?[index].pinnedPosition = wasPinned ? nil : position
            changed(preferredSavedIDs: [savedID])
            return
        }
    }

    public func moveWindow(id: String, to groupID: String, before windowID: String? = nil,
                           visibleOrderByGroup: [String: [String]]? = nil) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        if visibleOrderByGroup != nil { persistUnsavedLiveWindows() }
        let destination = windows(in: groupID).map(\.id).filter { $0 != id }
        let requestedPosition = windowID.flatMap { destination.firstIndex(of: $0) } ?? destination.count
        let movedKey = activeWindows[id].map { WindowKey(appID: $0.appID, title: $0.title) }
        let pinnedSlots = Dictionary(uniqueKeysWithValues: groups.map {
            ($0.id, pinnedPositions(in: $0.id).filter { $0.0 != movedKey })
        })
        if savedIDByWindowID[id] == nil {
            guard let window = activeWindows[id] else { return }
            let saved = SavedWindow(id: UUID().uuidString, appID: window.appID,
                                    title: window.title, documentURL: window.documentURL)
            savedIDByWindowID[id] = saved.id
            let beforeSavedID = windowID.flatMap { savedIDByWindowID[$0] }
            let index = beforeSavedID.flatMap { id in
                windowsByGroup[groupID, default: []].firstIndex(where: { $0.id == id })
            } ?? windowsByGroup[groupID, default: []].endIndex
            windowsByGroup[groupID, default: []].insert(saved, at: index)
            positionDraggedWindow(savedID: saved.id, in: groupID, requested: requestedPosition)
            changed(preferredSavedIDs: [saved.id], pinnedSlots: pinnedSlots,
                    visibleOrderByGroup: visibleOrderByGroup)
            return
        }
        guard let savedID = savedIDByWindowID[id] else { return }
        let beforeSavedID = windowID.flatMap { savedIDByWindowID[$0] }
        if beforeSavedID == savedID { return }
        if let window = activeWindows[id] { updateSavedWindow(id: savedID, from: window) }

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
        positionDraggedWindow(savedID: moved.id, in: groupID, requested: requestedPosition)
        changed(preferredSavedIDs: [moved.id], pinnedSlots: pinnedSlots,
                visibleOrderByGroup: visibleOrderByGroup)
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
        guard !window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "application\u{0}\(window.appID)"
        }
        return "title\u{0}\(window.appID)\u{0}\(window.title)"
    }

    private func matchKeys(_ window: WindowInfo) -> [String] {
        var keys = window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : ["title\u{0}\(window.appID)\u{0}\(window.title)"]
        if let documentURL = window.documentURL, !documentURL.isEmpty {
            keys.append("document\u{0}\(window.appID)\u{0}\(documentURL)")
        } else if keys.isEmpty {
            keys.append("application\u{0}\(window.appID)")
        }
        return keys
    }

    private func matchKeys(_ window: SavedWindow) -> [String] {
        var keys = window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : ["title\u{0}\(window.appID)\u{0}\(window.title)"]
        if let documentURL = window.documentURL, !documentURL.isEmpty {
            keys.append("document\u{0}\(window.appID)\u{0}\(documentURL)")
        } else if keys.isEmpty {
            keys.append("application\u{0}\(window.appID)")
        }
        return keys
    }

    private func restoreBindings(for windows: [WindowInfo]) {
        guard Set(windows.map(\.id)) != Set(activeWindows.keys) else { return }
        let liveKeyCounts = Dictionary(grouping: windows.flatMap(matchKeys), by: { $0 }).mapValues(\.count)
        var savedByKey: [String: [String]] = [:]
        for group in groups {
            for saved in windowsByGroup[group.id, default: []] {
                for key in matchKeys(saved) {
                    savedByKey[key, default: []].append(saved.id)
                }
            }
        }

        let liveIDs = Set(windows.map(\.id))
        var usedSavedIDs = Set(savedIDByWindowID.filter { liveIDs.contains($0.key) }.values)
        for window in windows.reversed() where savedIDByWindowID[window.id] == nil {
            let groupKey = window.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "application\u{0}\(window.appID)"
                : "title\u{0}\(window.appID)\u{0}\(window.title)"
            let key = liveKeyCounts[groupKey, default: 0] > 1 && savedByKey[groupKey]?.count == 1
                ? groupKey : preferredMatchKey(window)
            guard let key, let candidates = savedByKey[key], candidates.count == 1,
                  let savedID = candidates.first, !usedSavedIDs.contains(savedID) else { continue }
            savedIDByWindowID = savedIDByWindowID.filter { $0.value != savedID }
            savedIDByWindowID[window.id] = savedID
            usedSavedIDs.insert(savedID)
        }
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

    private func changed(preferredSavedIDs: [String] = [],
                         pinnedSlots: [String: [(WindowKey, Int)]] = [:],
                         visibleOrderByGroup: [String: [String]]? = nil) {
        _ = normalizeDuplicateRecords(preferredSavedIDs: preferredSavedIDs, pinnedSlots: pinnedSlots)
        if let visibleOrderByGroup {
            for (groupID, visibleIDs) in visibleOrderByGroup where groups.contains(where: { $0.id == groupID }) {
                alignSavedOrder(in: groupID, with: visibleIDs)
            }
            if let movedID = preferredSavedIDs.first,
               let groupID = groups.first(where: { group in
                   windowsByGroup[group.id, default: []].contains { $0.id == movedID }
               })?.id,
               let visibleIDs = visibleOrderByGroup[groupID],
               let position = visibleIDs.firstIndex(where: { savedIDByWindowID[$0] == movedID }),
               let index = windowsByGroup[groupID]?.firstIndex(where: { $0.id == movedID }),
               windowsByGroup[groupID]?[index].pinnedPosition != nil {
                windowsByGroup[groupID]?[index].pinnedPosition = position
            }
        }
        save()
        revision += 1
    }

    private func persistUnsavedLiveWindows() {
        for id in activeWindowOrder where savedIDByWindowID[id] == nil {
            guard let window = activeWindows[id] else { continue }
            let saved = SavedWindow(id: UUID().uuidString, appID: window.appID,
                                    title: window.title, documentURL: window.documentURL)
            windowsByGroup[Self.ungroupedID, default: []].append(saved)
            savedIDByWindowID[id] = saved.id
        }
    }

    private func alignSavedOrder(in groupID: String, with visibleIDs: [String]) {
        guard var records = windowsByGroup[groupID] else { return }
        let ranks = Dictionary(uniqueKeysWithValues: visibleIDs.enumerated().compactMap { offset, id
            -> (String, Int)? in
            savedIDByWindowID[id].map { ($0, offset) }
        })
        let activeIndices = records.indices.filter { ranks[records[$0].id] != nil }
        let ordered = activeIndices.map { records[$0] }.sorted {
            ranks[$0.id, default: .max] < ranks[$1.id, default: .max]
        }
        for (index, record) in zip(activeIndices, ordered) { records[index] = record }
        windowsByGroup[groupID] = records
    }

    @discardableResult
    private func pinnedPositions(in groupID: String) -> [(WindowKey, Int)] {
        windowsByGroup[groupID, default: []].compactMap { saved in
            saved.pinnedPosition.map { (WindowKey(appID: saved.appID, title: saved.title), $0) }
        }
    }

    private func positionDraggedWindow(savedID: String, in groupID: String, requested: Int) {
        guard let index = windowsByGroup[groupID]?.firstIndex(where: { $0.id == savedID }) else { return }
        let moved = windowsByGroup[groupID]![index]
        let key = WindowKey(appID: moved.appID, title: moved.title)
        guard moved.pinnedPosition != nil || windowsByGroup[groupID, default: []].contains(where: {
            $0.id != savedID && $0.appID == key.appID && $0.title == key.title && $0.pinnedPosition != nil
        }) else { return }
        let visibleCount = windows(in: groupID).count
        let occupied = Set(windowsByGroup[groupID, default: []].compactMap { saved -> Int? in
            guard saved.id != savedID,
                  !(saved.appID == key.appID && saved.title == key.title) else { return nil }
            return saved.pinnedPosition
        })
        let liveSavedIDs = Set(savedIDByWindowID.filter { activeWindows[$0.key] != nil }.values)
        let duplicateCount = windowsByGroup[groupID, default: []].filter {
            $0.id != savedID && liveSavedIDs.contains($0.id)
                && $0.appID == key.appID && $0.title == key.title
        }.count
        windowsByGroup[groupID]?[index].pinnedPosition = Self.availablePinnedPosition(
            requested, occupied: occupied, count: max(1, visibleCount - duplicateCount)
        )
    }

    private func normalizeDuplicateRecords(preferredSavedIDs: [String] = [],
                                           pinnedSlots: [String: [(WindowKey, Int)]] = [:]) -> Bool {
        let priority = Dictionary(uniqueKeysWithValues: preferredSavedIDs.enumerated().map { ($0.element, $0.offset) })
        var normalized = false
        for group in groups {
            let oldWindows = windowsByGroup[group.id, default: []]
            let slots = pinnedSlots[group.id] ?? pinnedPositions(in: group.id)
            var winnerByKey: [WindowKey: Int] = [:]
            for (index, saved) in oldWindows.enumerated() {
                let key = WindowKey(appID: saved.appID, title: saved.title)
                if let previous = winnerByKey[key],
                   priority[oldWindows[previous].id, default: -1] > priority[saved.id, default: -1] {
                    continue
                }
                winnerByKey[key] = index
            }
            let pinnedKeys = Set(oldWindows.filter { $0.pinnedPosition != nil }
                .map { WindowKey(appID: $0.appID, title: $0.title) })
            var keptWindows = oldWindows.enumerated().compactMap { index, saved -> SavedWindow? in
                let key = WindowKey(appID: saved.appID, title: saved.title)
                guard winnerByKey[key] == index else { return nil }
                var winner = saved
                if winner.pinnedPosition == nil, pinnedKeys.contains(key) {
                    winner.pinnedPosition = oldWindows.first(where: {
                        $0.appID == key.appID && $0.title == key.title && $0.pinnedPosition != nil
                    })?.pinnedPosition
                }
                return winner
            }
            var seenPinnedKeys = Set<WindowKey>()
            let distinctSlots = slots.filter { seenPinnedKeys.insert($0.0).inserted }
            for (key, index) in distinctSlots.sorted(by: { $0.1 < $1.1 }) {
                guard let current = keptWindows.firstIndex(where: {
                    $0.appID == key.appID && $0.title == key.title && $0.pinnedPosition != nil
                }) else { continue }
                var pinned = keptWindows.remove(at: current)
                pinned.pinnedPosition = index
                keptWindows.insert(pinned, at: min(index, keptWindows.count))
            }
            if keptWindows != oldWindows {
                windowsByGroup[group.id] = keptWindows
                normalized = true
            }
        }
        let retainedIDs = Set(windowsByGroup.values.flatMap { $0.map(\.id) })
        savedIDByWindowID = savedIDByWindowID.filter { retainedIDs.contains($0.value) }
        return normalized
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        var cleaned = false
        do {
            let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: fileURL))
            let ids = state.groups.map(\.id)
            let savedCount = state.windowsByGroup.values.reduce(0) { $0 + $1.count }
            guard ids.first == Self.ungroupedID, state.groups.first?.name == "未分组",
                  Set(ids).count == ids.count,
                  Set(state.windowsByGroup.keys).isSubset(of: Set(ids)),
                  state.windowsByGroup.values.flatMap({ $0 }).allSatisfy({
                      $0.pinnedPosition.map { $0 >= 0 } ?? true
                  }),
                  Set(state.windowsByGroup.values.flatMap { $0.map(\.id) }).count == savedCount else {
                throw CocoaError(.fileReadCorruptFile)
            }
            groups = state.groups
            windowsByGroup = state.windowsByGroup
            for id in ids where windowsByGroup[id] == nil { windowsByGroup[id] = [] }
            cleaned = normalizeDuplicateRecords()
        } catch {
            persistenceBlocked = true
            persistenceError = "无法读取分组数据：\(error.localizedDescription)"
            return
        }
        if cleaned { save() }
    }

    private func save() {
        guard !persistenceBlocked else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let persistedWindows = Dictionary(uniqueKeysWithValues: groups.map { group in
                (group.id, windowsByGroup[group.id, default: []])
            })
            let data = try JSONEncoder().encode(State(groups: groups, windowsByGroup: persistedWindows))
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "无法保存分组数据：\(error.localizedDescription)"
        }
    }
}
