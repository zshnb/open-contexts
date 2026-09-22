import XCTest
@testable import OpenContextsCore

final class WindowEligibilityTests: XCTestCase {
    func testAuxiliaryWindowsAreExcludedDespiteTitles() {
        XCTAssertFalse(include(.attributes(role: "AXWindow", subrole: "AXDialog"), hasTitle: true))
        XCTAssertFalse(include(.attributes(role: "AXWindow", subrole: "AXUnknown"), hasTitle: true))
        XCTAssertFalse(include(.attributes(role: "AXWindow", subrole: "AXSystemDialog"), hasTitle: true))
    }

    func testTaskWindowsRemainEligible() {
        XCTAssertTrue(include(.attributes(role: "AXWindow", subrole: "AXStandardWindow"), hasTitle: true))
        XCTAssertTrue(include(.attributes(role: "AXWindow", subrole: "AXDialog"), isModal: true))
        XCTAssertTrue(include(.attributes(role: "AXWindow", subrole: "AXSystemDialog"), isModal: true))
        XCTAssertTrue(include(.attributes(role: "AXWindow", subrole: "AXDialog"),
                              taskCapability: .supported))
        XCTAssertTrue(include(.attributes(role: "AXWindow", subrole: "AXUnknown"),
                              taskCapability: .supported))
        XCTAssertFalse(include(.attributes(role: "AXWindow", subrole: "AXFloatingWindow")))
        XCTAssertFalse(include(.attributes(role: "AXPopover", subrole: nil)))
        XCTAssertFalse(include(.attributes(role: "AXWindow", subrole: nil)))
    }

    func testNonModalSystemDialogIsExcludedDespiteTaskCapability() {
        let systemDialog = WindowCandidateState.attributes(role: "AXWindow", subrole: "AXSystemDialog")
        XCTAssertFalse(include(systemDialog, taskCapability: .supported))
        XCTAssertFalse(include(systemDialog, taskCapability: .supported, previouslyTracked: true))
    }

    func testSystemDialogUnknownModalStatusOnlyRetainsKnownWindow() {
        let systemDialog = WindowCandidateState.attributes(role: "AXWindow", subrole: "AXSystemDialog")
        XCTAssertFalse(include(systemDialog, modalStatusUnknown: true, taskCapability: .supported))
        XCTAssertTrue(include(systemDialog, modalStatusUnknown: true,
                              taskCapability: .supported, previouslyTracked: true))
    }

    func testTransientFailureRetainsKnownWindowButConfirmedRemovalDoesNot() {
        XCTAssertTrue(include(.attributeReadFailed, previouslyTracked: true))
        XCTAssertTrue(include(.missingRole, previouslyTracked: true))
        XCTAssertFalse(include(.attributeReadFailed, previouslyTracked: false))
        XCTAssertFalse(include(.notListed, previouslyTracked: true))
        XCTAssertTrue(include(.attributes(role: "AXWindow", subrole: "AXDialog"),
                              taskCapability: .readFailed, previouslyTracked: true))
        XCTAssertFalse(include(.attributes(role: "AXWindow", subrole: "AXDialog"),
                               hasTitle: true, previouslyTracked: true))
    }

    func testBlankWindowRequiresOrdinaryWindowCapability() {
        let standard = WindowCandidateState.attributes(role: "AXWindow", subrole: "AXStandardWindow")
        XCTAssertFalse(include(standard))
        XCTAssertTrue(include(standard, taskCapability: .supported))
        XCTAssertTrue(include(standard, hasTitle: true))
        XCTAssertTrue(include(standard, hasDocument: true))
        XCTAssertFalse(include(standard, taskCapability: .readFailed))
        XCTAssertTrue(include(standard, taskCapability: .readFailed, previouslyTracked: true))
    }

    private func include(
        _ state: WindowCandidateState,
        hasTitle: Bool = false,
        hasDocument: Bool = false,
        isModal: Bool = false,
        modalStatusUnknown: Bool = false,
        taskCapability: WindowTaskCapability = .unsupported,
        previouslyTracked: Bool = false
    ) -> Bool {
        WindowEligibilityPolicy.shouldInclude(
            state,
            hasTitle: hasTitle,
            hasDocument: hasDocument,
            isModal: isModal,
            modalStatusUnknown: modalStatusUnknown,
            taskCapability: taskCapability,
            previouslyTracked: previouslyTracked
        )
    }
}
