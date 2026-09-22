import XCTest
@testable import OpenContextsCore

final class IconRetryScheduleTests: XCTestCase {
    func testRetriesStopAfterSuccessOrExhaustionAndResetOnRecreation() {
        var successful = IconRetrySchedule()
        XCTAssertEqual(successful.nextDelay(), 1)
        successful.stop()
        XCTAssertNil(successful.nextDelay())

        var exhausted = IconRetrySchedule()
        XCTAssertEqual([exhausted.nextDelay(), exhausted.nextDelay(), exhausted.nextDelay()], [1, 3, 10])
        XCTAssertTrue(exhausted.isExhausted)
        XCTAssertNil(exhausted.nextDelay())

        var reopened = IconRetrySchedule()
        XCTAssertEqual(reopened.nextDelay(), 1)
    }
}
