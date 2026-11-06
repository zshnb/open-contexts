import CoreGraphics

public enum SwitcherDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case primaryDisplay
    case focusedDisplay

    public var id: String { rawValue }

    /// `displays` must follow `NSScreen.screens` order, where the first entry is the primary display.
    public func targetDisplays<ID: Equatable>(from displays: [ID], focused: ID? = nil) -> [ID] {
        switch self {
        case .allDisplays:
            displays
        case .primaryDisplay:
            Array(displays.prefix(1))
        case .focusedDisplay:
            if let focused, displays.contains(focused) { [focused] } else { Array(displays.prefix(1)) }
        }
    }

    /// Returns the display overlapping `frame` the most, or nil when nothing overlaps.
    public static func display<ID>(containing frame: CGRect, in displays: [(id: ID, bounds: CGRect)]) -> ID? {
        var selected: ID?
        var largestArea: CGFloat = 0
        for display in displays {
            let overlap = display.bounds.intersection(frame)
            guard !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > largestArea {
                selected = display.id
                largestArea = area
            }
        }
        return selected
    }
}
