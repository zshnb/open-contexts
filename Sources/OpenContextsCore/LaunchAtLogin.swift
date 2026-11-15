/// Login item status as reported by the system. The system owns this state, so users can also change it in
/// System Settings → General → Login Items.
public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    /// Registered, but the user must allow it in System Settings → Login Items before it takes effect.
    case requiresApproval
    /// The system cannot find the app as a login item, e.g. an unbundled debug build.
    case unavailable
}

public protocol LoginItemRegistry: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
    func unregister() throws
}

public struct LaunchAtLoginState: Equatable, Sendable {
    public var status: LaunchAtLoginStatus
    public var errorDescription: String?

    public init(status: LaunchAtLoginStatus, errorDescription: String? = nil) {
        self.status = status
        self.errorDescription = errorDescription
    }

    /// A registration awaiting approval stays on so the toggle matches the user's choice.
    public var isOn: Bool { status == .enabled || status == .requiresApproval }
    public var needsApproval: Bool { status == .requiresApproval }

    /// Registers or unregisters the app, then re-reads the status so the result always reflects the system.
    public static func set(_ enabled: Bool, using registry: LoginItemRegistry) -> LaunchAtLoginState {
        guard LaunchAtLoginState(status: registry.status).isOn != enabled else {
            return LaunchAtLoginState(status: registry.status)
        }
        do {
            try enabled ? registry.register() : registry.unregister()
            return LaunchAtLoginState(status: registry.status)
        } catch {
            return LaunchAtLoginState(status: registry.status, errorDescription: error.localizedDescription)
        }
    }
}
