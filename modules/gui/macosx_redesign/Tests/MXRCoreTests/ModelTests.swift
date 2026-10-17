import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// A controllable clock source for interpolation tests.
@MainActor
private final class FakeClockSource: PlaybackClockSource {
    var timerPoint: TimerPoint? { didSet { events.send(.updated) } }
    private let events = EventChannel<ClockEvent>()
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) { events.add(owner, handler: handler) }
}

@MainActor
private final class HostTimeBox {
    var value: CFTimeInterval
    init(_ value: CFTimeInterval) { self.value = value }
}

@MainActor
final class PlaybackClockTests: XCTestCase {
    func testInterpolatesWhileRunningAndClamps() {
        let source = FakeClockSource()
        let now = HostTimeBox(100)
        let clock = PlaybackClock(source: source, now: { now.value }, schedulesTicks: false)
        XCTAssertFalse(clock.hasMedia)

        source.timerPoint = TimerPoint(time: .seconds(130), length: .hms(0, 25, 40), position: 0.08, rate: 1, hostTime: 100)
        XCTAssertTrue(clock.isRunning)
        XCTAssertEqual(clock.displaySecond, 130)
        XCTAssertEqual(clock.length, .hms(0, 25, 40))

        XCTAssertEqual(clock.time(at: 101.5).seconds, 131.5, accuracy: 0.001)
        now.value = 102.2
        XCTAssertEqual(clock.currentTime.seconds, 132.2, accuracy: 0.001)
        XCTAssertEqual(clock.position(at: 100), 130.0 / 1540.0, accuracy: 0.0001)
        // Clamped to the length.
        XCTAssertEqual(clock.time(at: 100 + 10_000), .hms(0, 25, 40))
        // Display second only changes when refreshed (by a point or a scheduled tick).
        source.timerPoint = TimerPoint(time: .seconds(132.2), length: .hms(0, 25, 40), position: 0.09, rate: 1, hostTime: 102.2)
        XCTAssertEqual(clock.displaySecond, 132)
        XCTAssertEqual(clock.displayRemaining, .hms(0, 25, 40) - .seconds(132))
    }

    func testRateAndPausedPoints() {
        let source = FakeClockSource()
        let clock = PlaybackClock(source: source, now: { 10 }, schedulesTicks: false)
        source.timerPoint = TimerPoint(time: .seconds(60), length: .seconds(600), position: 0.1, rate: 2, hostTime: 8)
        XCTAssertEqual(clock.time(at: 10).seconds, 64, accuracy: 0.001)
        source.timerPoint = TimerPoint(time: .seconds(64), length: .seconds(600), position: 0.1, rate: 2, hostTime: nil)
        XCTAssertFalse(clock.isRunning)
        XCTAssertEqual(clock.time(at: 1_000), .seconds(64))
        source.timerPoint = nil
        XCTAssertFalse(clock.hasMedia)
        XCTAssertEqual(clock.time(at: 1_000), .zero)
    }

    func testMockClockIsFrozenByDefault() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.clock.displaySecond, 130)
        XCTAssertFalse(app.clock.isRunning)
        XCTAssertEqual(app.clock.length, .hms(0, 25, 40))
        app.player.seek(to: .hms(0, 10, 0))
        XCTAssertEqual(app.clock.displaySecond, 600)
    }

    func testRealtimeMockAdvances() async throws {
        let app = AppModel.mock(.playingMovie, clock: .realtime)
        XCTAssertTrue(app.clock.isRunning)
        let start = app.clock.currentTime
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertGreaterThan(app.clock.currentTime.seconds, start.seconds + 0.4)
        XCTAssertGreaterThanOrEqual(app.clock.displaySecond, 130)
        app.player.pause()
        XCTAssertFalse(app.clock.isRunning)
    }
}

@MainActor
final class PlayerModelTests: XCTestCase {
    func testScenarioState() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.player.state, .playing)
        XCTAssertTrue(app.player.isPlaying)
        XCTAssertEqual(app.player.windowTitle, "The Wand S01E04")
        XCTAssertEqual(app.player.media?.folder?.name, "S01")
        XCTAssertTrue(app.player.canSeek)

        let idle = AppModel.mock(.idle)
        XCTAssertEqual(idle.player.windowTitle, "VLC Media Player")
        XCTAssertTrue(idle.player.isStopped)
    }

    func testTransportTransitions() {
        let app = AppModel.mock(.pausedEpisode)
        XCTAssertEqual(app.player.state, .paused)
        app.player.togglePlayPause()
        XCTAssertEqual(app.player.state, .playing)
        app.player.togglePlayPause()
        XCTAssertEqual(app.player.state, .paused)
        app.player.stop()
        XCTAssertEqual(app.player.state, .stopped)
        XCTAssertNil(app.player.media)
        XCTAssertFalse(app.clock.hasMedia)
    }

    func testVolumeAndRate() {
        let app = AppModel.mock(.playingEpisode)
        app.player.setVolume(3)
        XCTAssertEqual(app.player.volume, 2)
        XCTAssertEqual(app.player.volumePercent, 200)
        app.player.toggleMute()
        XCTAssertTrue(app.player.isMuted)
        app.player.setVolume(0.5)
        XCTAssertFalse(app.player.isMuted, "raising the volume unmutes")
        app.player.setRate(10)
        XCTAssertEqual(app.player.rate, 4)
        app.perform(.slower)
        XCTAssertEqual(app.player.rate, 3)
        app.perform(.normalRate)
        XCTAssertEqual(app.player.rate, 1)
    }

    func testJumpAndSeekClamp() {
        let app = AppModel.mock(.playingEpisode)
        app.player.jump(by: -1_000)
        XCTAssertEqual(app.clock.displaySecond, 0)
        app.player.seek(toPosition: 2)
        XCTAssertEqual(app.clock.displayTime, .hms(0, 25, 40))
    }

    func testRestorePromptResume() {
        let app = AppModel.mock(.continueWatching)
        XCTAssertEqual(app.player.restorePrompt?.time, .hms(0, 45, 8))
        XCTAssertEqual(app.clock.displaySecond, 0)
        app.player.resumePlayback()
        XCTAssertNil(app.player.restorePrompt)
        XCTAssertEqual(app.clock.displayTime, .hms(0, 45, 8))
    }

    func testRestorePromptTimesOut() async throws {
        let backend = MockBackend(scenario: .continueWatching)
        let player = PlayerModel(backend: backend.player)
        player.restorePromptTimeout = .milliseconds(50)
        backend.player.askRestore(at: .seconds(5))
        XCTAssertNotNil(player.restorePrompt)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(player.restorePrompt)
        XCTAssertEqual(backend.player.time, .zero)
    }

    func testSleepTimerEndOfItemSetsQueueAction() {
        let app = AppModel.mock(.playingEpisode)
        app.player.setSleepTimer(.endOfItem)
        XCTAssertEqual(app.queue.mediaStoppedAction, .pause)
        app.player.pause()
        XCTAssertEqual(app.player.sleepTimer, .off)
        XCTAssertEqual(app.queue.mediaStoppedAction, .continue)
        app.player.setSleepTimer(.minutes30)
        XCTAssertNotNil(app.player.sleepDeadline)
        app.player.setSleepTimer(.off)
        XCTAssertNil(app.player.sleepDeadline)
    }

    func testABLoopCycle() {
        let app = AppModel.mock(.playingMovie)
        app.player.toggleABLoop()
        guard case .pointA = app.player.abLoop else { return XCTFail("expected A") }
        app.player.seek(to: .hms(0, 3, 0))
        app.player.toggleABLoop()
        guard case .looping(let a, let b) = app.player.abLoop else { return XCTFail("expected loop") }
        XCTAssertEqual(a, .hms(0, 2, 10))
        XCTAssertEqual(b, .hms(0, 3, 0))
        app.player.toggleABLoop()
        XCTAssertEqual(app.player.abLoop, .off)
    }
}

@MainActor
final class QueueModelTests: XCTestCase {
    func testSummaryAndNavigation() {
        let app = AppModel.mock(.pausedEpisode)
        XCTAssertEqual(app.queue.items.count, 4)
        XCTAssertEqual(app.queue.summary, "4 items - 1h 34m")
        XCTAssertEqual(app.queue.items.map(\.media.duration), [.hms(0, 23, 6), .hms(0, 24, 18), .hms(0, 25, 0), .hms(0, 22, 35)])
        XCTAssertEqual(app.queue.currentItem?.media.fileName, "The_Wand_S01E11.mp4")
        XCTAssertTrue(app.queue.hasNext)
        XCTAssertFalse(app.queue.hasPrevious)
        app.queue.next()
        XCTAssertEqual(app.queue.currentIndex, 1)
        XCTAssertEqual(app.player.media?.displayTitle, "The Wand S01E12")
        XCTAssertTrue(app.queue.hasPrevious)
        app.queue.previous()
        XCTAssertEqual(app.queue.currentIndex, 0)
    }

    func testEditing() throws {
        let app = AppModel.mock(.pausedEpisode)
        let ids = app.queue.items.map(\.id)
        app.queue.move([ids[3]], to: 1)
        XCTAssertEqual(app.queue.items.map(\.id), [ids[0], ids[3], ids[1], ids[2]])
        XCTAssertEqual(app.queue.currentIndex, 0)
        app.queue.selection = [ids[1], ids[2]]
        app.queue.removeSelection()
        XCTAssertEqual(app.queue.items.map(\.id), [ids[0], ids[3]])
        XCTAssertTrue(app.queue.selection.isEmpty)
        let movie = try XCTUnwrap(app.backends.library as? MockLibrary).mediaItem(id: MockDatabase.dontBlinkID)!
        app.queue.playNext([movie])
        XCTAssertEqual(app.queue.items[1].media.id, movie.id)
        app.queue.enqueue([movie])
        XCTAssertEqual(app.queue.items.last?.media.id, movie.id)
        XCTAssertEqual(app.queue.summary.hasPrefix("4 items"), true)
        app.queue.clear()
        XCTAssertTrue(app.queue.isEmpty)
        XCTAssertNil(app.player.media)
    }

    func testModesAndPlayNow() {
        let app = AppModel.mock(.idle)
        XCTAssertTrue(app.queue.isEmpty)
        app.queue.cycleRepeatMode()
        XCTAssertEqual(app.queue.repeatMode, .all)
        app.queue.cycleRepeatMode()
        XCTAssertEqual(app.queue.repeatMode, .one)
        app.queue.toggleShuffle()
        XCTAssertTrue(app.queue.isShuffled)
        app.open(urls: [URL(fileURLWithPath: "/tmp/a.mp4"), URL(fileURLWithPath: "/tmp/b.mp4")])
        XCTAssertEqual(app.queue.items.count, 2)
        XCTAssertEqual(app.player.media?.fileName, "a.mp4")
        XCTAssertEqual(app.player.state, .playing)
        app.queue.sort(by: .title, ascending: false)
        XCTAssertEqual(app.queue.items.map { $0.media.fileName }, ["b.mp4", "a.mp4"])
        XCTAssertEqual(app.queue.currentItem?.media.fileName, "a.mp4")
    }

    func testRealtimeEndAdvancesAndMarksWatched() async throws {
        let backend = MockBackend(scenario: .music, clock: .realtime)
        let app = backend.makeAppModel(clockTicks: false)
        app.player.seek(to: .hms(0, 1, 39) + .milliseconds(900))
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(app.queue.currentIndex, 1)
        XCTAssertEqual(app.player.media?.title, "moonlight")
        XCTAssertEqual(backend.library.mediaItem(id: MockDatabase.untangleID)?.playCount, 4)
    }
}

@MainActor
final class TracksModelTests: XCTestCase {
    func testTrackListsMatchFigma() {
        let app = AppModel.mock(.playingEpisode)
        XCTAssertEqual(app.tracks.embeddedTracks(of: .subtitle).map(\.name), ["English", "Japanese"])
        XCTAssertEqual(app.tracks.externalTracks(of: .subtitle).map(\.name), ["The_Wand_S01_EN.srt"])
        XCTAssertEqual(app.tracks.selectedTrack(of: .subtitle)?.name, "English")
        XCTAssertEqual(app.tracks.audioTracks.map(\.name), ["English", "Japanese"])
        XCTAssertEqual(app.tracks.selectedTrack(of: .audio)?.name, "Japanese")
        XCTAssertEqual(app.tracks.videoTracks.map(\.name), ["Track 1"])
        XCTAssertEqual(app.tracks.audioDevices.map(\.name), ["Speakers", "Headphones"])
        XCTAssertEqual(app.tracks.currentAudioDevice?.name, "Headphones")
    }

    func testSelectionNoneCycleAndExternal() {
        let app = AppModel.mock(.playingEpisode)
        app.tracks.selectNone(.subtitle)
        XCTAssertTrue(app.tracks.isNoneSelected(.subtitle))
        app.tracks.cycle(.subtitle)
        XCTAssertEqual(app.tracks.selectedTrack(of: .subtitle)?.name, "English")
        app.tracks.select(app.tracks.subtitleTracks[1])
        XCTAssertEqual(app.tracks.selectedTrack(of: .subtitle)?.name, "Japanese")
        XCTAssertEqual(app.tracks.subtitleTracks.filter(\.isSelected).count, 1)
        app.tracks.addExternalTrack(url: URL(fileURLWithPath: "/tmp/The_Wand_S01E04_Spanish.srt"))
        XCTAssertEqual(app.tracks.selectedTrack(of: .subtitle)?.name, "The_Wand_S01E04_Spanish.srt")
        XCTAssertEqual(app.tracks.selectedTrack(of: .subtitle)?.language, "Spanish")
        app.tracks.selectAudioDevice(app.tracks.audioDevices[0])
        XCTAssertEqual(app.tracks.currentAudioDevice?.name, "Speakers")
    }

    func testDelaysStyleAndCues() async throws {
        let app = AppModel.mock(.playingEpisode)
        app.tracks.nudgeSubtitleDelay(steps: -3)
        XCTAssertEqual(app.tracks.subtitleDelay, .milliseconds(-150))
        app.tracks.setAudioDelay(.milliseconds(200))
        XCTAssertEqual(app.tracks.audioDelay, .milliseconds(200))
        app.tracks.updateSubtitleStyle { $0.bold = true; $0.sizeMode = .pixels }
        XCTAssertTrue(app.tracks.subtitleStyle.bold)
        XCTAssertEqual(app.tracks.subtitleStyle.sizeMode, .pixels)
        app.tracks.setSubtitleTextScale(1_000)
        XCTAssertEqual(app.tracks.subtitleTextScale, 500)
        app.tracks.loadSubtitleCues()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(app.tracks.subtitleCues.isEmpty)
        XCTAssertTrue(zip(app.tracks.subtitleCues, app.tracks.subtitleCues.dropFirst()).allSatisfy { $0.end <= $1.start })
    }

    func testEffectsModels() {
        let app = AppModel.mock(.playingMovie)
        app.videoEffects.update { $0.flip = .horizontal }
        XCTAssertEqual(app.videoEffects.effects.flip, .horizontal)
        XCTAssertTrue(app.videoEffects.isModified)
        app.videoEffects.reset()
        XCTAssertFalse(app.videoEffects.isModified)
        let rock = EqualizerPreset.builtIn.first { $0.id == "rock" }!
        app.audioEffects.applyEqualizerPreset(rock)
        XCTAssertTrue(app.audioEffects.effects.equalizer.isEnabled)
        XCTAssertEqual(app.audioEffects.selectedEqualizerPreset?.title, "Rock")
        app.audioEffects.setEqualizerBand(0, gain: 30)
        XCTAssertEqual(app.audioEffects.effects.equalizer.bands[0], 20)
        XCTAssertNil(app.audioEffects.selectedEqualizerPreset)
        app.audioEffects.applyEqualizerPreset(EqualizerPreset.builtIn[0])
        XCTAssertFalse(app.audioEffects.effects.equalizer.isEnabled)
    }

    func testChaptersAndBookmarks() async throws {
        let app = AppModel.mock(.playingMovie)
        XCTAssertEqual(app.chapters.chapters.map(\.name), ["Winter", "Spring", "Summer", "Fall", "Winter (5 Years Later)"])
        XCTAssertEqual(app.chapters.currentChapter?.name, nil, "00:02:10 is before the first chapter at 00:02:15")
        app.chapters.select(app.chapters.chapters[2])
        XCTAssertEqual(app.clock.displayTime, .hms(0, 51, 30))
        XCTAssertEqual(app.chapters.currentChapter?.name, "Summer")
        app.chapters.nextChapter()
        XCTAssertEqual(app.chapters.currentChapter?.name, "Fall")

        XCTAssertEqual(app.bookmarks.bookmarks.map(\.name), ["DON’T BLINK 1", "DON’T BLINK 2"])
        XCTAssertEqual(app.bookmarks.summary, "2 Bookmarks")
        XCTAssertEqual(app.bookmarks.bookmarks[0].time.formatted(.hoursMinutesSecondsMilliseconds), "00:00:42:023")
        app.perform(.addBookmark)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(app.bookmarks.bookmarks.count, 3)
        XCTAssertEqual(app.bookmarks.bookmarks.last?.name, "DON’T BLINK 3")
        app.bookmarks.jump(to: app.bookmarks.bookmarks[0])
        XCTAssertEqual(app.clock.displaySecond, 42)
    }
}
