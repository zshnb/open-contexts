public enum SwitcherDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case allDisplays
    case primaryDisplay

    public var id: String { rawValue }

    /// `displays` must follow `NSScreen.screens` order, where the first entry is the primary display.
    public func targetDisplays<ID>(from displays: [ID]) -> [ID] {
        switch self {
        case .allDisplays: displays
        case .primaryDisplay: Array(displays.prefix(1))
        }
    }
}
