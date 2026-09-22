public enum WindowCandidateState: Equatable, Sendable {
    case notListed
    case attributeReadFailed
    case missingRole
    case attributes(role: String, subrole: String?)
}

public enum WindowTaskCapability: Equatable, Sendable {
    case supported
    case unsupported
    case readFailed
}

public enum WindowEligibilityPolicy {
    public static func shouldInclude(
        _ state: WindowCandidateState,
        hasTitle: Bool,
        hasDocument: Bool,
        isModal: Bool,
        modalStatusUnknown: Bool,
        taskCapability: WindowTaskCapability,
        previouslyTracked: Bool
    ) -> Bool {
        let isStandardWindow: Bool
        switch state {
        case .notListed:
            return false
        case .attributeReadFailed, .missingRole:
            return previouslyTracked
        case let .attributes(role, subrole):
            guard role == "AXWindow" else { return false }
            switch subrole {
            case "AXStandardWindow":
                isStandardWindow = true
            case "AXFloatingWindow", "AXSystemFloatingWindow", "AXPopover", "AXTooltip":
                return false
            default:
                isStandardWindow = false
            }
        }
        if isStandardWindow, hasTitle || hasDocument { return true }
        if !isStandardWindow, isModal { return true }
        if state == .attributes(role: "AXWindow", subrole: "AXSystemDialog") {
            return modalStatusUnknown && previouslyTracked
        }
        if state == .attributes(role: "AXWindow", subrole: "AXDialog"),
           !modalStatusUnknown, !isModal, !hasTitle, !hasDocument {
            return false
        }
        switch taskCapability {
        case .supported: return true
        case .readFailed: return previouslyTracked
        case .unsupported: return false
        }
    }
}
