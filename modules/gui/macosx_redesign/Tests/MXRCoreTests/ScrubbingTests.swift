import CoreGraphics
import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// D028 scrub session, seek-preview throttling and the D031 paused-seek still.
@MainActor
private final class ScrubClockSource: PlaybackClockSource {
    var timerPoint: TimerPoint? { didSet { events.send(.updated) } }
    private let events = EventChannel<ClockEvent>()
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) { events.add(owner, handler: handler) }
}

@MainActor
private final class HostClock {
    var value: CFTimeInterval = 100
}

@MainActor
final class ScrubbingTests: XCTestCase {
    private func runningPoint(_ seconds: Double, host: CFTimeInterval) -> TimerPoint {
        TimerPoint(time: .seconds(seconds), length: .seconds(600), position: seconds / 600, rate: 1, hostTime: host)
    }

    func testClockFollowsTheScrubAndIgnoresStalePoints() {
        let source = ScrubClockSource()
        let host = HostClock()
        let clock = PlaybackClock(source: source, now: { host.value }, schedulesTicks: false)
        source.timerPoint = runningPoint(30, host: 100)
        XCTAssertTrue(clock.isRunning)

        clock.beginScrub(at: .seconds(200))
        XCTAssertEqual(clock.displaySecond, 200, "the elapsed label follows the pointer")
        XCTAssertFalse(clock.isRunning, "no per-frame drawing while the pointer drives the head")
        clock.scrub(to: .seconds(250))
        XCTAssertEqual(clock.currentTime, .seconds(250))
        XCTAssertEqual(clock.position(at: 500), 250.0 / 600, accuracy: 0.0001)

        // A stale pre-seek running point must not pull the label back (BB-03).
        host.value = 100.2
        source.timerPoint = runningPoint(30.2, host: 100.2)
        XCTAssertEqual(clock.displaySecond, 250)

        clock.endScrub(at: .seconds(260))
        XCTAssertEqual(clock.displaySecond, 260)
        // The engine's seek point (target, not running) does not end the hold while playing...
        source.timerPoint = TimerPoint(time: .seconds(260), length: .seconds(600), position: 0.43, rate: 1, hostTime: nil)
        XCTAssertTrue(clock.isScrubbing)
        // ...another stale running point neither...
        source.timerPoint = runningPoint(30.4, host: 100.4)
        XCTAssertEqual(clock.displaySecond, 260, "the playhead does not snap back after release")
        // ...the first running point at the target does.
        host.value = 100.6
        source.timerPoint = runningPoint(260.1, host: 100.6)
        XCTAssertFalse(clock.isScrubbing)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.displaySecond, 260)
    }

    func testPausedScrubSettlesOnTheSeekPoint() {
        let source = ScrubClockSource()
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        source.timerPoint = TimerPoint(time: .seconds(30), length: .seconds(600), position: 0.05, rate: 1, hostTime: nil)
        clock.beginScrub(at: .seconds(90))
        clock.endScrub(at: .seconds(90))
        source.timerPoint = TimerPoint(time: .seconds(90), length: .seconds(600), position: 0.15, rate: 1, hostTime: nil)
        XCTAssertFalse(clock.isScrubbing)
        XCTAssertEqual(clock.displaySecond, 90)
    }

    func testScrubHoldTimesOut() async throws {
        let source = ScrubClockSource()
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        clock.scrubSettleTimeout = .milliseconds(20)
        source.timerPoint = runningPoint(30, host: 100)
        clock.beginScrub(at: .seconds(300))
        clock.endScrub(at: .seconds(300))
        XCTAssertTrue(clock.isScrubbing)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertFalse(clock.isScrubbing, "an unconfirmed seek gives the clock back to the engine")
        XCTAssertEqual(clock.displaySecond, 30)
    }

    func testClickSendsOnePreciseSeek() {
        let source = ScrubClockSource()
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        source.timerPoint = runningPoint(30, host: 100)
        var seeks: [(MediaTime, SeekPrecision)] = []
        let session = ScrubSession(clock: clock) { seeks.append(($0, $1)) }
        session.update(to: .seconds(120))
        session.end(at: .seconds(120))
        XCTAssertEqual(seeks.count, 1, "BB-13: a click does not send FAST then PRECISE")
        XCTAssertEqual(seeks.first?.0, .seconds(120))
        XCTAssertEqual(seeks.first?.1, .precise)
    }

    func testDragCoalescesFastSeeksLatestWins() async throws {
        let source = ScrubClockSource()
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        source.timerPoint = runningPoint(30, host: 100)
        var seeks: [(MediaTime, SeekPrecision)] = []
        let session = ScrubSession(clock: clock) { seeks.append(($0, $1)) }
        session.interval = .milliseconds(60)
        session.restDelay = .seconds(10)
        for second in stride(from: 100.0, through: 140, by: 1) { session.update(to: .seconds(second)) }
        XCTAssertEqual(clock.displaySecond, 140, "the label follows every event")
        XCTAssertTrue(seeks.isEmpty, "the first FAST seek waits one interval")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(seeks.count, 1, "41 pointer events produced one engine seek")
        XCTAssertEqual(seeks.last?.0, .seconds(140), "latest target wins")
        XCTAssertEqual(seeks.last?.1, .fast)
        session.end(at: .seconds(141))
        XCTAssertEqual(seeks.last?.1, .precise)
        XCTAssertEqual(seeks.count, 2)
    }

    func testRestingPointerLandsOnTheExactFrame() async throws {
        let source = ScrubClockSource()
        let clock = PlaybackClock(source: source, now: { 100 }, schedulesTicks: false)
        source.timerPoint = runningPoint(30, host: 100)
        var seeks: [(MediaTime, SeekPrecision)] = []
        let session = ScrubSession(clock: clock) { seeks.append(($0, $1)) }
        session.interval = .milliseconds(10)
        session.restDelay = .milliseconds(40)
        session.update(to: .seconds(200))
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(seeks.last?.0, .seconds(200))
        XCTAssertEqual(seeks.last?.1, .precise)
        session.cancel()
        XCTAssertFalse(clock.isScrubbing)
    }
}

/// A thumbnail backend whose requests complete only when the test says so.
@MainActor
private final class GatedThumbnails: ExactFrameThumbnailBackend {
    private(set) var requests: [(MediaTime, Bool)] = []
    private var gates: [CheckedContinuation<Void, Never>] = []
    var cancellations = 0
    var gated = true
    func artwork(for media: MediaItem, maxPixelSize: CGSize) async -> CGImage? { nil }
    func waveform(for media: MediaItem, bins: Int) async -> [Float]? { nil }
    func seekPreview(for media: MediaItem, at time: MediaTime, maxPixelSize: CGSize) async -> CGImage? {
        await seekPreview(for: media, at: time, exact: false, maxPixelSize: maxPixelSize)
    }
    func seekPreview(for media: MediaItem, at time: MediaTime, exact: Bool, maxPixelSize: CGSize) async -> CGImage? {
        requests.append((time, exact))
        if gated { await withCheckedContinuation { gates.append($0) } }
        if Task.isCancelled { cancellations += 1; return nil }
        return Self.image(width: Int(maxPixelSize.width), height: Int(maxPixelSize.height))
    }
    func open() { let all = gates; gates = []; all.forEach { $0.resume() } }
    static func image(width: Int, height: Int) -> CGImage? {
        CGContext(data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)?.makeImage()
    }
}

@MainActor
final class SeekPreviewThrottleTests: XCTestCase {
    func testLatestWinsWhileARequestRuns() async throws {
        let backend = MockBackend(scenario: .playingEpisode)
        let thumbnails = GatedThumbnails()
        let preview = SeekPreviewModel(thumbnails: thumbnails, player: backend.player)
        preview.debounce = .seconds(10)
        preview.staleAfter = .seconds(10)
        let q = SeekPreviewModel.quantum(for: backend.player.currentMedia?.duration).microseconds
        func middle(_ slot: Int64) -> MediaTime { MediaTime(microseconds: q * slot + q / 2) }
        preview.hover(at: middle(10))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(thumbnails.requests.count, 1, "the first slot is requested at once (no debounce)")
        for slot in Int64(11)...20 { preview.hover(at: middle(slot)) }
        XCTAssertEqual(thumbnails.requests.count, 1, "one request in flight")
        thumbnails.open()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNotNil(preview.image, "the card updates while the pointer keeps moving (BB-01)")
        XCTAssertEqual(thumbnails.requests.count, 2, "only the newest waiting slot follows")
        XCTAssertEqual(thumbnails.requests.last?.0, MediaTime(microseconds: q * 20))
        thumbnails.open()
        try await Task.sleep(for: .milliseconds(30))
        // Back to the first slot: served from the cache.
        preview.hover(at: MediaTime(microseconds: q * 10 + 1))
        XCTAssertEqual(thumbnails.requests.count, 2)
        XCTAssertNotNil(preview.image)
    }

    func testEndCancelsTheEngineRequest() async throws {
        let backend = MockBackend(scenario: .playingEpisode)
        let thumbnails = GatedThumbnails()
        let preview = SeekPreviewModel(thumbnails: thumbnails, player: backend.player)
        preview.hover(at: .seconds(300))
        try await Task.sleep(for: .milliseconds(20))
        preview.end()
        thumbnails.open()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(thumbnails.cancellations, 1)
        XCTAssertNil(preview.image)
    }

    func testRestingPointerRequestsTheExactFrame() async throws {
        let backend = MockBackend(scenario: .playingEpisode)
        let thumbnails = GatedThumbnails()
        thumbnails.gated = false
        let preview = SeekPreviewModel(thumbnails: thumbnails, player: backend.player)
        preview.debounce = .milliseconds(20)
        preview.hover(at: .seconds(301.23))
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(thumbnails.requests.last?.1, true)
        XCTAssertEqual(thumbnails.requests.last?.0, MediaTime(microseconds: 301_200_000))
    }
}

@MainActor
final class PausedSeekStillTests: XCTestCase {
    func testPausedSeekShowsTheExactFrameUntilPlaybackResumes() async throws {
        let backend = MockBackend(scenario: .pausedEpisode, clock: .realtime)
        let app = backend.makeAppModel(clockTicks: false)
        let thumbnails = GatedThumbnails()
        thumbnails.gated = false
        let still = PausedSeekFrameModel(thumbnails: thumbnails, player: app.player, clock: app.clock)
        still.settleDelay = .zero
        still.resumeGrace = .milliseconds(10)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(still.image, "pausing alone keeps the engine's frame")

        app.player.seek(to: .seconds(400), precision: .precise)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(thumbnails.requests.last?.0, .seconds(400))
        XCTAssertEqual(thumbnails.requests.last?.1, true, "the still is the exact frame")
        XCTAssertNotNil(still.image)
        XCTAssertEqual(still.time, .seconds(400))

        app.player.play()
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(still.image, "real frames replace the still once playback resumes")
    }
}
