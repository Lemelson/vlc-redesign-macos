import XCTest
@testable import MXRCore

final class VideoClickTimingTests: XCTestCase {
    func testDisabledDoubleClickDoesNotReserveTheSystemInterval() {
        for interval in [0.2, 0.5, 1.0] {
            XCTAssertEqual(VideoClickTiming.singleClickDelay(doubleClickEnabled: false, systemInterval: interval), 0)
        }
    }

    func testEnabledDoubleClickKeepsTheSystemIntervalForCancellation() {
        for interval in [0.2, 0.5, 1.0] {
            XCTAssertEqual(VideoClickTiming.singleClickDelay(doubleClickEnabled: true, systemInterval: interval), interval)
        }
    }
}
