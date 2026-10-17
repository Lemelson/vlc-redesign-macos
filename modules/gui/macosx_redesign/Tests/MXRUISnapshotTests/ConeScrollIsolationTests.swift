import AppKit
import XCTest
import MXRCore
import MXRMockBackend
@testable import MXRUI

@MainActor final class ConeScrollIsolationTests: XCTestCase {
    func testModalWheelNeitherChangesVolumeNorConsumesEvent() {
        let app = MockBackend(scenario: .pausedEpisode).makeAppModel(clockTicks: false)
        var input = ConeScrollInput()
        let initial = app.player.volume
        XCTAssertTrue(input.handle(delta: 1, precise: false, enabled: ConeScrollAvailability.isEnabled(in: app), ended: false) { app.player.adjustVolume(steps: $0) })
        XCTAssertEqual(app.player.volume, initial + app.player.volumeStep, accuracy: 0.001)
        app.interface.present(.about)
        let beforeModalWheel = app.player.volume
        XCTAssertFalse(input.handle(delta: 3, precise: false, enabled: ConeScrollAvailability.isEnabled(in: app), ended: false) { app.player.adjustVolume(steps: $0) })
        XCTAssertEqual(app.player.volume, beforeModalWheel)
    }
    func testDisabledWheelResetsFractionalMotionAndUnavailableSurfacePassesThrough() {
        let app = MockBackend(scenario: .pausedEpisode).makeAppModel(clockTicks: false)
        var input = ConeScrollInput()
        var steps = 0
        _ = input.handle(delta: 6, precise: true, enabled: true, ended: false) { steps += $0 }
        XCTAssertFalse(input.handle(delta: 0, precise: true, enabled: false, ended: false) { steps += $0 })
        _ = input.handle(delta: 6, precise: true, enabled: true, ended: false) { steps += $0 }
        XCTAssertEqual(steps, 0, "A disabled cone must discard its partial pre-modal scroll")
        app.interface.isUIHidden = true
        XCTAssertFalse(ConeScrollAvailability.isEnabled(in: app))
        app.interface.isUIHidden = false
        app.interface.isControlBarVisible = false
        XCTAssertFalse(ConeScrollAvailability.isEnabled(in: app))
    }

    /// B-03: natural scrolling and the reverse preference each flip the gesture once, as on the video.
    func testConeFollowsTheVideoScrollDirection() {
        func steps(_ delta: CGFloat, natural: Bool, reversed: Bool) -> Int {
            var input = ConeScrollInput(), total = 0
            _ = input.handle(delta: delta, precise: false, natural: natural, reversed: reversed, enabled: true, ended: false) { total += $0 }
            return total
        }
        XCTAssertEqual(steps(2, natural: false, reversed: false), 2)
        XCTAssertEqual(steps(-2, natural: true, reversed: false), 2, "A natural-scrolling swipe up (negative delta) is louder")
        XCTAssertEqual(steps(2, natural: false, reversed: true), -2)
        XCTAssertEqual(steps(-2, natural: true, reversed: true), -2)
    }

    /// B-02: the cone holds no AppKit view, so the image engine renders it (no placeholder).
    func testConeScrollMonitorPassesEventsThroughUnlessHovered() {
        let monitor = ConeScrollMonitor()
        var total = 0
        monitor.adjust = { total += $0 }
        monitor.enabled = true
        let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
        XCTAssertNotNil(event)
        monitor.hovered = false
        if let event { XCTAssertFalse(monitor.handle(event)) }
        XCTAssertEqual(total, 0)
    }
}
