import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import QuartzCore
@testable import MXRUI
import SwiftUI
import XCTest

/// B-01: the playhead layer follows the clock without any SwiftUI update (scrub, paused jump,
/// Reduce Motion seconds). These tests read the laid-out layer, not a geometry predicate.
@MainActor final class SeekProgressRedrawTests: XCTestCase {
    private func spin(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func progressView(in view: NSView) -> SeekProgressNSView? {
        if let match = view as? SeekProgressNSView { return match }
        for subview in view.subviews { if let match = progressView(in: subview) { return match } }
        return nil
    }

    private func expectedX(_ progress: Double, in view: SeekProgressNSView, head: Theme.Box = Theme.Metric.ControlBar.playhead) -> CGFloat {
        let width = view.bounds.width - SeekProgressView.inset * 2
        return PlayerGeometry.seekHeadX(progress: progress, width: width, headWidth: head.width)
    }

    private func hostedSeekBar(_ app: AppModel) -> (NSWindow, SeekProgressNSView) {
        let size = CGSize(width: Theme.Metric.ControlBar.seekTrack.width, height: Theme.Metric.ControlBar.seekTrack.height)
        let host = NSHostingView(rootView: MXRSeekBar().appModel(app).frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        spin()
        guard let view = progressView(in: host) else {
            XCTFail("The seek bar must host a SeekProgressNSView")
            return (window, SeekProgressNSView())
        }
        return (window, view)
    }

    func testHeadFollowsEveryScrubEventWhilePaused() {
        let app = MockBackend(scenario: .pausedEpisode).makeAppModel(clockTicks: false)
        XCTAssertFalse(app.clock.isRunning)
        let (window, view) = hostedSeekBar(app)
        defer { window.close() }
        let session = ScrubSession(clock: app.clock) { _, _ in }
        for progress in [0.2, 0.5, 0.8] {
            session.update(to: app.clock.length * progress)
            spin()
            XCTAssertEqual(view.renderedHeadX, expectedX(progress, in: view), accuracy: 0.5, "scrub to \(progress)")
        }
        session.cancel()
    }

    func testPausedJumpMovesTheHead() {
        let app = MockBackend(scenario: .pausedEpisode).makeAppModel(clockTicks: false)
        let (window, view) = hostedSeekBar(app)
        defer { window.close() }
        let before = view.renderedHeadX
        app.player.jump(by: .seconds(120))
        spin()
        XCTAssertGreaterThan(view.renderedHeadX, before + 1)
        XCTAssertEqual(view.renderedHeadX, expectedX(app.clock.currentPosition, in: view), accuracy: 0.5)
    }

    func testReduceMotionMovesTheHeadEachSecondWithoutADisplayLink() {
        let source = ManualClockSource()
        let length = MediaTime.seconds(100)
        source.timerPoint = TimerPoint(time: .seconds(10), length: length, position: 0.1, rate: 1, hostTime: CACurrentMediaTime())
        let clock = PlaybackClock(source: source, schedulesTicks: false)
        XCTAssertTrue(clock.isRunning)
        let view = SeekProgressNSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 24))
        view.configure(clock: clock, width: 996, head: Theme.Metric.ControlBar.playhead, samples: nil, resume: nil,
                       visible: true, reduceMotion: true, rate: 1, scheme: .dark, accent: .orange)
        XCTAssertFalse(view.isAnimating, "Reduce Motion never runs the per-frame loop")
        XCTAssertEqual(view.renderedHeadX, expectedX(0.1, in: view), accuracy: 0.5)

        source.timerPoint = TimerPoint(time: .seconds(50), length: length, position: 0.5, rate: 1, hostTime: CACurrentMediaTime())
        source.send(.updated)
        spin()
        XCTAssertEqual(view.renderedHeadX, expectedX(0.5, in: view), accuracy: 0.5)
        view.stop()
    }

    func testHiddenBarDoesNotAnimate() {
        let source = ManualClockSource()
        source.timerPoint = TimerPoint(time: .seconds(10), length: .seconds(100), position: 0.1, rate: 1, hostTime: CACurrentMediaTime())
        let clock = PlaybackClock(source: source, schedulesTicks: false)
        let view = SeekProgressNSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 24))
        view.configure(clock: clock, width: 996, head: Theme.Metric.ControlBar.playhead, samples: nil, resume: nil,
                       visible: false, reduceMotion: false, rate: 1, scheme: .dark, accent: .orange)
        XCTAssertFalse(view.isAnimating)
        // Not in a window either: nothing on screen to animate.
        view.configure(clock: clock, width: 996, head: Theme.Metric.ControlBar.playhead, samples: nil, resume: nil,
                       visible: true, reduceMotion: false, rate: 1, scheme: .dark, accent: .orange)
        XCTAssertFalse(view.isAnimating)
        view.stop()
    }
}

private final class ManualClockSource: PlaybackClockSource {
    var timerPoint: TimerPoint?
    private var handler: (@MainActor (ClockEvent) -> Void)?
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) { self.handler = handler }
    @MainActor func send(_ event: ClockEvent) { handler?(event) }
}
