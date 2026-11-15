import XCTest
@testable import OpenContextsCore

private struct RegistryError: Error, LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

private final class FakeRegistry: LoginItemRegistry {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus = .enabled
    var failure: Error?
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0

    init(_ status: LaunchAtLoginStatus) { self.status = status }

    func register() throws {
        registerCount += 1
        if let failure { throw failure }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCount += 1
        if let failure { throw failure }
        status = .disabled
    }
}

final class LaunchAtLoginTests: XCTestCase {
    func testStateReflectsSystemStatus() {
        XCTAssertTrue(LaunchAtLoginState(status: .enabled).isOn)
        XCTAssertTrue(LaunchAtLoginState(status: .requiresApproval).isOn)
        XCTAssertTrue(LaunchAtLoginState(status: .requiresApproval).needsApproval)
        XCTAssertFalse(LaunchAtLoginState(status: .disabled).isOn)
        XCTAssertFalse(LaunchAtLoginState(status: .unavailable).isOn)
        XCTAssertFalse(LaunchAtLoginState(status: .enabled).needsApproval)
    }

    func testEnablingRegistersTheApp() {
        let registry = FakeRegistry(.disabled)
        let state = LaunchAtLoginState.set(true, using: registry)
        XCTAssertEqual(registry.registerCount, 1)
        XCTAssertEqual(state, LaunchAtLoginState(status: .enabled))
    }

    func testDisablingUnregistersTheApp() {
        let registry = FakeRegistry(.enabled)
        let state = LaunchAtLoginState.set(false, using: registry)
        XCTAssertEqual(registry.unregisterCount, 1)
        XCTAssertEqual(state, LaunchAtLoginState(status: .disabled))
    }

    func testMatchingStatusSkipsRegistration() {
        let enabled = FakeRegistry(.enabled)
        XCTAssertTrue(LaunchAtLoginState.set(true, using: enabled).isOn)
        let disabled = FakeRegistry(.disabled)
        XCTAssertFalse(LaunchAtLoginState.set(false, using: disabled).isOn)
        let unavailable = FakeRegistry(.unavailable)
        XCTAssertFalse(LaunchAtLoginState.set(false, using: unavailable).isOn)
        XCTAssertEqual(enabled.registerCount + disabled.unregisterCount + unavailable.unregisterCount, 0)
    }

    func testRegistrationAwaitingApprovalStaysOnAndAsksForApproval() {
        let registry = FakeRegistry(.disabled)
        registry.statusAfterRegister = .requiresApproval
        let state = LaunchAtLoginState.set(true, using: registry)
        XCTAssertTrue(state.isOn)
        XCTAssertTrue(state.needsApproval)
        XCTAssertNil(state.errorDescription)
    }

    func testDisablingWhileAwaitingApprovalUnregisters() {
        let registry = FakeRegistry(.requiresApproval)
        let state = LaunchAtLoginState.set(false, using: registry)
        XCTAssertEqual(registry.unregisterCount, 1)
        XCTAssertFalse(state.isOn)
    }

    func testFailureKeepsSystemStatusAndReportsTheError() {
        let registry = FakeRegistry(.disabled)
        registry.failure = RegistryError()
        let enabling = LaunchAtLoginState.set(true, using: registry)
        XCTAssertFalse(enabling.isOn)
        XCTAssertEqual(enabling.errorDescription, "Operation not permitted")

        registry.status = .enabled
        let disabling = LaunchAtLoginState.set(false, using: registry)
        XCTAssertTrue(disabling.isOn)
        XCTAssertEqual(disabling.errorDescription, "Operation not permitted")
    }
}
