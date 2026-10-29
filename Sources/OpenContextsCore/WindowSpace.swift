import Foundation

public struct WindowSpace: Equatable, Sendable {
    public let id: UInt64
    public let index: Int
    public let isCurrent: Bool
    public let isFullscreen: Bool
    /// UUID of the display that owns this desktop, when the system reports one.
    public let displayID: String?

    public init(id: UInt64, index: Int, isCurrent: Bool, isFullscreen: Bool = false, displayID: String? = nil) {
        self.id = id
        self.index = index
        self.isCurrent = isCurrent
        self.isFullscreen = isFullscreen
        self.displayID = displayID
    }
}

public enum WindowSwitcher {
    /// Keeps windows whose desktop belongs to `display`. Windows without a known display stay visible,
    /// e.g. when displays share one set of desktops.
    public static func windows(_ windows: [WindowInfo], onDisplay display: String,
                               knownDisplays: Set<String>) -> [WindowInfo] {
        windows.filter { window in
            guard let owner = window.space?.displayID, knownDisplays.contains(owner) else { return true }
            return owner == display
        }
    }

    public static func filter(_ windows: [WindowInfo], query: String, allSpaces: Bool) -> [WindowSearch.Match] {
        guard allSpaces else { return WindowSearch.filter(windows.filter(\.isOnCurrentSpace), query: query) }
        let ordered = windows.enumerated().sorted { lhs, rhs in
            let a = lhs.element, b = rhs.element
            if a.isOnCurrentSpace != b.isOnCurrentSpace { return a.isOnCurrentSpace }
            if a.space?.id != b.space?.id {
                return (a.space?.index ?? 0) < (b.space?.index ?? 0)
            }
            if a.isOnCurrentSpace { return lhs.offset < rhs.offset }
            let appOrder = a.appName.localizedStandardCompare(b.appName)
            if appOrder != .orderedSame { return appOrder == .orderedAscending }
            let titleOrder = a.displayTitle.localizedStandardCompare(b.displayTitle)
            return titleOrder == .orderedSame ? a.id < b.id : titleOrder == .orderedAscending
        }.map(\.element)
        var results: [WindowSearch.Match] = []
        var group: [WindowInfo] = []
        for window in ordered {
            if let previous = group.last, previous.space?.id != window.space?.id {
                results += WindowSearch.filter(group, query: query)
                group.removeAll(keepingCapacity: true)
            }
            group.append(window)
        }
        return results + WindowSearch.filter(group, query: query)
    }
}
