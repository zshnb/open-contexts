import Foundation

public enum DockBadgeRead: Equatable, Sendable {
    case value(String?)
    case failure
}

public struct DockBadgeState: Equatable, Sendable {
    public private(set) var badges: [String: String] = [:]

    public init() {}

    public mutating func merge(activeAppIDs: Set<String>, reads: [String: DockBadgeRead]?) {
        badges = badges.filter { activeAppIDs.contains($0.key) }
        guard let reads else { return }
        for (appID, read) in reads where activeAppIDs.contains(appID) {
            switch read {
            case let .value(raw):
                badges[appID] = Self.displayValue(raw)
            case .failure:
                break
            }
        }
    }

    public static func appID(for applicationURL: URL) -> String? {
        let url = applicationURL.standardizedFileURL
        guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { return nil }
        return Bundle(url: url)?.bundleIdentifier ?? url.path
    }

    public static func displayValue(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let count = Int(value), count >= 0 {
            if count == 0 { return nil }
            return count > 99 ? "99+" : String(count)
        }
        if value.hasSuffix("+"), let count = Int(value.dropLast()), count > 0 {
            return count >= 99 ? "99+" : "\(count)+"
        }
        return "•"
    }
}
