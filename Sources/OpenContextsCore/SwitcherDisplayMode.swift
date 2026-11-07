import CoreGraphics

public enum SwitcherDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case primaryDisplay
    case focusedDisplay
    case pointerDisplay

    public var id: String { rawValue }

    /// Whether the mode shows the switcher on one display resolved when it opens.
    public var usesAnchorDisplay: Bool {
        switch self {
        case .allDisplays, .primaryDisplay: false
        case .focusedDisplay, .pointerDisplay: true
        }
    }

    /// `displays` must follow `NSScreen.screens` order, where the first entry is the primary display.
    public func targetDisplays<ID: Equatable>(from displays: [ID], anchor: ID? = nil) -> [ID] {
        switch self {
        case .allDisplays:
            displays
        case .primaryDisplay:
            Array(displays.prefix(1))
        case .focusedDisplay, .pointerDisplay:
            if let anchor, displays.contains(anchor) { [anchor] } else { Array(displays.prefix(1)) }
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
