import Foundation

/// Most-recently-used window order: the focused window moves to the front, other windows keep their order.
///
/// While a switch the user requested is in flight, its target counts as focused. Desktop transitions briefly
/// focus other windows, and recording those would push the window the user came from out of second place.
public struct RecentWindowOrder: Sendable {
    /// How long a finished switch keeps holding focus while waiting for the target to be observed as focused.
    public static let settleTimeout: TimeInterval = 0.5

    public private(set) var ids: [String] = []
    public private(set) var focusedID: String?
    private var activationID: String?
    private var settleDeadline: TimeInterval?

    public init() {}

    /// Drops closed windows, appends new ones in `windowIDs` order and moves the focused window to the front.
    public mutating func update(windowIDs: [String], focusedID observed: String?, now: TimeInterval) {
        if activationID != nil, let settleDeadline, observed == activationID || now >= settleDeadline {
            cancelActivation()
        }
        let live = Set(windowIDs)
        var ordered = ids.filter(live.contains)
        var known = Set(ordered)
        for id in windowIDs where known.insert(id).inserted { ordered.append(id) }
        ids = ordered
        focusedID = activationID ?? observed
        if let focusedID { moveToFront(focusedID) }
    }

    /// Records that the user asked to switch to `id`; it moves to the front and counts as focused right away.
    public mutating func beginActivation(_ id: String) {
        activationID = id
        settleDeadline = nil
        focusedID = id
        moveToFront(id)
    }

    /// Called when the switch to the window passed to `beginActivation` has been requested from the system.
    /// Focus keeps being held until the target is observed as focused or `settleTimeout` passes.
    public mutating func finishActivation(now: TimeInterval) {
        guard activationID != nil else { return }
        settleDeadline = now + Self.settleTimeout
    }

    /// Called when the switch was cancelled or superseded; observed focus is recorded again.
    public mutating func cancelActivation() {
        activationID = nil
        settleDeadline = nil
    }

    private mutating func moveToFront(_ id: String) {
        guard let index = ids.firstIndex(of: id), index != 0 else { return }
        ids.remove(at: index)
        ids.insert(id, at: 0)
    }
}
