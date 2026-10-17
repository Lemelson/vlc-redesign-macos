import Foundation
import MXRCore
import Observation
@testable import MXRUI
import XCTest

@MainActor
private final class MiniSeekClockSource: PlaybackClockSource {
    var timerPoint: TimerPoint? { didSet { events.send(.updated) } }
    private let events = EventChannel<ClockEvent>()
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) {
        events.add(owner, handler: handler)
    }
}

/// Observation callbacks are Sendable; the flag may be read safely without actor assumptions.
private final class MiniSeekInvalidation: @unchecked Sendable {
    private let lock = NSLock()
    private var invalidated = false
    func mark() { lock.withLock { invalidated = true } }
    var value: Bool { lock.withLock { invalidated } }
}

@MainActor
final class MiniPlayerSeekBindingTests: XCTestCase {
    private func point(_ seconds: Double) -> TimerPoint {
        TimerPoint(time: .seconds(seconds), length: .seconds(10), position: seconds / 10, rate: 1, hostTime: 100)
    }

    func testFillObservesFractionalScrubMovesWithinOneSecond() {
        let source = MiniSeekClockSource()
        source.timerPoint = point(1)
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        let session = ScrubSession(clock: clock) { _, _ in }
        defer { session.cancel() }
        session.update(to: .seconds(2.1))
        let changed = MiniSeekInvalidation()
        let initial = withObservationTracking {
            MiniSeekBar.fraction(clock: clock)
        } onChange: { changed.mark() }
        XCTAssertEqual(initial, 0.21, accuracy: 0.000001)

        session.update(to: .seconds(2.9))
        XCTAssertEqual(clock.displaySecond, 2, "The spoken timestamp deliberately stays at whole seconds")
        XCTAssertTrue(changed.value, "The fill binding must invalidate even when displaySecond is unchanged")
        XCTAssertEqual(MiniSeekBar.fraction(clock: clock), 0.29, accuracy: 0.000001)
        XCTAssertEqual(MiniSeekBar.fraction(clock: clock) * 377, 109.33, accuracy: 0.001)
    }

    func testPlayingTimerPointsKeepTheFillOnCoarseUpdates() {
        let source = MiniSeekClockSource()
        source.timerPoint = point(2.1)
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        let changed = MiniSeekInvalidation()
        let initial = withObservationTracking {
            MiniSeekBar.fraction(clock: clock)
        } onChange: { changed.mark() }
        XCTAssertEqual(initial, 0.2, accuracy: 0.000001)

        source.timerPoint = point(2.9)
        XCTAssertFalse(changed.value, "Ordinary subsecond engine updates must not invalidate the mini fill")
        XCTAssertEqual(MiniSeekBar.fraction(clock: clock), 0.2, accuracy: 0.000001)
        source.timerPoint = point(3.1)
        XCTAssertTrue(changed.value, "The next displayed second still redraws the fill")
        XCTAssertEqual(MiniSeekBar.fraction(clock: clock), 0.3, accuracy: 0.000001)
    }

    func testReleasedSeekKeepsItsFractionUntilClockCancellation() {
        let source = MiniSeekClockSource()
        source.timerPoint = point(1)
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        let session = ScrubSession(clock: clock) { _, _ in }
        session.update(to: .seconds(2.9))
        session.end(at: .seconds(2.9))
        let changed = MiniSeekInvalidation()
        let released = withObservationTracking {
            MiniSeekBar.fraction(clock: clock)
        } onChange: { changed.mark() }
        XCTAssertEqual(released, 0.29, accuracy: 0.000001)

        clock.cancelScrub()
        XCTAssertTrue(changed.value, "Ending the precise hold must redraw the binding")
        XCTAssertEqual(MiniSeekBar.fraction(clock: clock), 0.1, accuracy: 0.000001)
    }
}
