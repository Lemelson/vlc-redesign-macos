import Foundation
import Observation
import QuartzCore

/// Playback time for the UI, separate from ``PlayerModel`` so ticks only invalidate time views.
///
/// - Bind text labels to ``displaySecond`` (changes at most once per second).
/// - Draw the playhead from a small view that interpolates ``position(at:)`` (for example inside a
///   `TimelineView` limited to the head and fill), only while ``isRunning`` and the bar is visible
///   (ARCHITECTURE §8). Observe ``revision`` to redraw when a paused point changes.
/// - Scrubbing (D028): while a ``ScrubSession`` is active the clock reports the pointer's target, so
///   the elapsed label and the playhead follow the pointer on every event, and stale engine points
///   cannot pull them back until the final seek has landed.
@MainActor
@Observable
public final class PlaybackClock {
    /// Whole seconds of the current time (floor). Observed by time labels.
    public private(set) var displaySecond: Int = 0
    /// Media length; zero when unknown or live. Observed.
    public private(set) var length: MediaTime = .zero
    /// True while time advances by itself (playing, not frozen, not scrubbing). Observed: start and
    /// stop per-frame drawing on it.
    public private(set) var isRunning: Bool = false
    /// True when something is loaded.
    public private(set) var hasMedia: Bool = false
    /// Changes whenever the timer point or the scrub target changes. Observed by views that draw a
    /// sub-second position while ``isRunning`` is false (a paused seek moves the head without
    /// changing ``displaySecond``).
    public private(set) var revision: Int = 0
    /// The target of the active scrub, nil when not scrubbing. While set, ``time(at:)``,
    /// ``position(at:)`` and ``displaySecond`` report it.
    public private(set) var scrubTime: MediaTime?

    @ObservationIgnored private let source: any PlaybackClockSource
    @ObservationIgnored private let now: @MainActor () -> CFTimeInterval
    @ObservationIgnored private let schedulesTicks: Bool
    @ObservationIgnored private var point: TimerPoint?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var scrub: ScrubPhase?
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    /// How long a released scrub may wait for the engine to confirm the seek before the clock
    /// follows the engine again.
    @ObservationIgnored public var scrubSettleTimeout: Duration = .milliseconds(1500)

    private enum ScrubPhase {
        /// The pointer drives the clock. `wasRunning`: playback was running when the scrub began.
        case dragging(wasRunning: Bool)
        /// Released: hold `target` until a matching engine point arrives (or the timeout).
        case settling(target: MediaTime, since: CFTimeInterval, wasRunning: Bool)
    }

    /// Creates a clock fed by `source`.
    /// - Parameters:
    ///   - now: host time in the `CACurrentMediaTime()` base; injectable for tests.
    ///   - schedulesTicks: when true, the clock wakes itself on second boundaries while running so
    ///     ``displaySecond`` stays exact between timer points. Tests pass false.
    public init(source: any PlaybackClockSource,
                now: @escaping @MainActor () -> CFTimeInterval = { CACurrentMediaTime() },
                schedulesTicks: Bool = true) {
        self.source = source
        self.now = now
        self.schedulesTicks = schedulesTicks
        source.addListener(self) { [weak self] event in
            self?.handle(event)
        }
        reload()
    }

    /// The media time at `hostTime` (`vlc_player_timer_point_Interpolate` semantics), clamped to
    /// `0...length` when the length is known; the scrub target while scrubbing. Not observed.
    public func time(at hostTime: CFTimeInterval) -> MediaTime {
        if let scrubTime { return scrubTime }
        return Self.interpolate(point, at: hostTime)
    }

    /// The position 0...1 at `hostTime`. Not observed.
    public func position(at hostTime: CFTimeInterval) -> Double {
        guard let point else { return 0 }
        guard point.length > .zero else { return scrubTime == nil ? point.position : 0 }
        return min(max(time(at: hostTime).seconds / point.length.seconds, 0), 1)
    }

    /// The current time (reads the host clock). Not observed; use ``displaySecond`` in views.
    public var currentTime: MediaTime { time(at: now()) }

    /// The current position 0...1. Not observed.
    public var currentPosition: Double { position(at: now()) }

    /// ``displaySecond`` as a `MediaTime`, for formatting.
    public var displayTime: MediaTime { .seconds(Double(displaySecond)) }

    /// Remaining time at second precision (`length - displayTime`), for the "-00:23:30" label.
    public var displayRemaining: MediaTime { length > .zero ? max(.zero, length - displayTime) : .zero }

    /// Re-reads the source (also called on every event).
    public func reload() {
        point = source.timerPoint
        hasMedia = point != nil
        let newLength = point?.length ?? .zero
        if newLength != length { length = newLength }
        settleIfConfirmed()
        updateRunning()
        revision &+= 1
        refreshDisplaySecond()
        scheduleTick()
    }

    // MARK: Scrubbing (D028)

    /// True between ``beginScrub(at:)`` and the moment the engine confirmed the released seek.
    public var isScrubbing: Bool { scrub != nil }

    /// Starts following the pointer at `target`. Called by ``ScrubSession``.
    public func beginScrub(at target: MediaTime) {
        settleTask?.cancel()
        settleTask = nil
        let wasRunning: Bool
        switch scrub {
        case .dragging(let running)?, .settling(_, _, let running)?: wasRunning = running
        case nil: wasRunning = isRunning
        }
        scrub = .dragging(wasRunning: wasRunning)
        setScrubTime(target)
    }

    /// Moves the scrub target (every pointer event). Ignored when no scrub is active.
    public func scrub(to target: MediaTime) {
        guard case .dragging = scrub else { return }
        setScrubTime(target)
    }

    /// The pointer was released at `target` and the final seek was sent: keep showing `target`
    /// until the engine reports a point there, so stale pre-seek points do not snap the playhead
    /// back (BB-03).
    public func endScrub(at target: MediaTime) {
        let wasRunning: Bool
        switch scrub {
        case .dragging(let running)?, .settling(_, _, let running)?: wasRunning = running
        case nil: wasRunning = isRunning
        }
        scrub = .settling(target: target, since: now(), wasRunning: wasRunning)
        setScrubTime(target)
        settleTask?.cancel()
        let timeout = scrubSettleTimeout
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, case .settling = self.scrub else { return }
            self.finishScrub()
        }
        settleIfConfirmed()
    }

    /// Drops the scrub at once (media change, cancelled drag) and follows the engine again.
    public func cancelScrub() {
        guard scrub != nil else { return }
        finishScrub()
    }

    private func setScrubTime(_ target: MediaTime) {
        let clamped = length > .zero ? target.clamped(to: .zero...length) : max(.zero, target)
        if scrubTime != clamped { scrubTime = clamped }
        revision &+= 1
        updateRunning()
        refreshDisplaySecond()
        scheduleTick()
    }

    private func finishScrub() {
        settleTask?.cancel()
        settleTask = nil
        scrub = nil
        scrubTime = nil
        updateRunning()
        revision &+= 1
        refreshDisplaySecond()
        scheduleTick()
    }

    /// A released scrub ends when the engine reports a point near the target: a running point
    /// when playback was running (stale running points from before the seek are far away), any
    /// point when paused.
    private func settleIfConfirmed() {
        guard case .settling(let target, let since, let wasRunning)? = scrub else { return }
        guard let point else { finishScrub(); return }
        let running = point.hostTime != nil && point.rate != 0
        guard running || !wasRunning else { return }
        let host = now()
        let reported = Self.interpolate(point, at: host)
        let slack = Self.settleTolerance + max(0, host - since) * max(1, abs(point.rate))
        if abs((reported - target).seconds) <= slack { finishScrub() }
    }

    /// How far (seconds) a confirming point may be from the released target.
    private static let settleTolerance = 0.75

    // MARK: Engine events

    private func handle(_ event: ClockEvent) {
        switch event {
        case .updated, .discontinuity:
            reload()
        case .reset:
            if scrub != nil { scrub = nil; scrubTime = nil; settleTask?.cancel(); settleTask = nil }
            reload()
        }
    }

    private func updateRunning() {
        let running = scrubTime == nil && point?.hostTime != nil && (point?.rate ?? 0) != 0
        if running != isRunning { isRunning = running }
    }

    private func refreshDisplaySecond() {
        let seconds = Int(floor(currentTime.seconds))
        if seconds != displaySecond { displaySecond = seconds }
    }

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = nil
        guard schedulesTicks, isRunning, let point, point.rate > 0 else { return }
        let current = currentTime.seconds
        let toNext = (floor(current) + 1 - current) / point.rate
        let delay = max(0.01, toNext + 0.002)
        tickTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.refreshDisplaySecond()
            self.scheduleTick()
        }
    }

    private static func interpolate(_ point: TimerPoint?, at hostTime: CFTimeInterval) -> MediaTime {
        guard let point else { return .zero }
        guard let pointHost = point.hostTime, point.rate != 0 else { return point.time }
        let elapsed = max(0, hostTime - pointHost) * point.rate
        var time = point.time + .seconds(elapsed)
        if point.length > .zero { time = time.clamped(to: .zero...point.length) }
        return time
    }
}

/// D028 scrub session: the pointer drives ``PlaybackClock`` on every event, while engine seeks are
/// coalesced. While dragging, at most one FAST seek per ``interval`` is sent and the latest target
/// always wins; when the pointer rests for ``restDelay`` one PRECISE seek lands on the frame under
/// it; release sends one PRECISE seek. A plain click therefore sends a single PRECISE seek.
@MainActor
public final class ScrubSession {
    public typealias Seek = @MainActor (MediaTime, SeekPrecision) -> Void

    /// Minimum spacing between FAST seeks while dragging (~10 Hz, like Qt's SeekSlider).
    public var interval: Duration = .milliseconds(100)
    /// The pointer must rest this long before an exact-frame seek is sent during the drag.
    public var restDelay: Duration = .milliseconds(220)

    private let clock: PlaybackClock
    private let seek: Seek
    public private(set) var isActive = false
    private var lastSent: ContinuousClock.Instant?
    private var pending: MediaTime?
    private var flushTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?

    public init(clock: PlaybackClock, seek: @escaping Seek) {
        self.clock = clock
        self.seek = seek
    }

    /// The pointer went down or moved to `target`.
    public func update(to target: MediaTime) {
        if !isActive {
            isActive = true
            clock.beginScrub(at: target)
            // Defer the first FAST seek by one interval: a click releases before it fires.
            lastSent = .now
        } else {
            clock.scrub(to: target)
        }
        pending = target
        flush()
        scheduleRest()
    }

    /// The pointer was released at `target`: one PRECISE seek, then the clock settles on it.
    public func end(at target: MediaTime) {
        cancelTimers()
        if !isActive { clock.beginScrub(at: target) }
        clock.endScrub(at: target)
        seek(target, .precise)
        reset()
    }

    /// Abandons the scrub without a final seek.
    public func cancel() {
        cancelTimers()
        if isActive { clock.cancelScrub() }
        reset()
    }

    private func flush() {
        guard let target = pending else { return }
        let now = ContinuousClock.now
        if let lastSent, now - lastSent < interval {
            guard flushTask == nil else { return } // the scheduled send picks up the newest target
            let wait = interval - (now - lastSent)
            flushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                self.flushTask = nil
                self.flush()
            }
            return
        }
        pending = nil
        lastSent = now
        seek(target, .fast)
    }

    private func scheduleRest() {
        restTask?.cancel()
        let delay = restDelay
        restTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.isActive, let target = self.clock.scrubTime else { return }
            self.flushTask?.cancel()
            self.flushTask = nil
            self.pending = nil
            self.lastSent = .now
            self.seek(target, .precise)
        }
    }

    private func cancelTimers() {
        flushTask?.cancel(); flushTask = nil
        restTask?.cancel(); restTask = nil
    }

    private func reset() {
        isActive = false
        pending = nil
        lastSent = nil
    }
}
