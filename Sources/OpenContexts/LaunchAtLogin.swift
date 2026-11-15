import AppKit
import OpenContextsCore
import ServiceManagement

final class MainAppLoginItem: LoginItemRegistry {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .disabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Mirrors the system login item for the Settings toggle. Nothing is stored in UserDefaults because users can
/// also change the login item in System Settings.
@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state: LaunchAtLoginState
    private let registry: LoginItemRegistry

    init(registry: LoginItemRegistry = MainAppLoginItem()) {
        self.registry = registry
        state = LaunchAtLoginState(status: registry.status)
    }

    func refresh() {
        let status = registry.status
        guard status != state.status else { return }
        state = LaunchAtLoginState(status: status)
    }

    func setEnabled(_ enabled: Bool) {
        state = LaunchAtLoginState.set(enabled, using: registry)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func selfCheck() -> Bool {
        final class Registry: LoginItemRegistry {
            var status = LaunchAtLoginStatus.disabled
            func register() throws { status = .requiresApproval }
            func unregister() throws { status = .disabled }
        }
        let registry = Registry()
        let controller = LaunchAtLoginController(registry: registry)
        guard !controller.state.isOn else { return false }
        controller.setEnabled(true)
        guard controller.state.isOn, controller.state.needsApproval else { return false }
        // Approving or removing the login item in System Settings shows up on the next refresh.
        registry.status = .enabled
        controller.refresh()
        guard controller.state == LaunchAtLoginState(status: .enabled) else { return false }
        registry.status = .disabled
        controller.refresh()
        return !controller.state.isOn
    }
}
