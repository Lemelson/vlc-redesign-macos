import XCTest
import CoreGraphics
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class MediaRequestRaceTests: XCTestCase {
    func testPreviewRequestsSameTimeAgainAfterMediaChanges() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        let previews = SeekPreviewModel(thumbnails: mock.thumbnails, player: mock.player)
        previews.debounce = .zero
        previews.hover(at: .seconds(100))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(mock.thumbnails.seekPreviewRequests, 1)
        var next = try XCTUnwrap(mock.player.currentMedia)
        next.id = "different-media"
        mock.player.load(next)
        previews.hover(at: .seconds(100))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(mock.thumbnails.seekPreviewRequests, 2, "The same time in another media requires a new frame")
    }

    func testPendingSubtitleCuesCannotReappearAfterMediaStops() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        let delayed = DelayedCuesPlayer(player: mock.player)
        let tracks = TracksModel(backend: delayed)
        tracks.loadSubtitleCues()
        await delayed.waitForRequest()
        mock.player.load(nil)
        delayed.finish([SubtitleCue(start: .zero, end: .seconds(2), text: "Old media")])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(tracks.subtitleCues.isEmpty, "A completed old-media request must not repopulate the timeline")
    }

    func testStereoOutputSerializesRequestsAndRestoresIdleAfterFailure() async {
        let mock = MockBackend(scenario: .playingEpisode)
        let delayed = DelayedCuesPlayer(player: mock.player)
        let effects = AudioEffectsModel(backend: delayed)
        let state = mock.player.state
        let media = mock.player.currentMedia
        let volume = mock.player.volume
        let originalEffects = mock.player.audioEffects
        let test = Task { await effects.testStereoOutput() }
        await delayed.waitForStereoRequest()
        XCTAssertTrue(effects.isTestingOutput)
        await effects.testStereoOutput()
        XCTAssertEqual(delayed.stereoRequests, 1, "A second click must not start another isolated player.")
        delayed.finishStereo(BackendOperationError.invalidInput("The output device disconnected."))
        await test.value
        XCTAssertFalse(effects.isTestingOutput)
        XCTAssertEqual(effects.testOutputError, "The output device disconnected.")
        XCTAssertEqual(mock.player.state, state)
        XCTAssertEqual(mock.player.currentMedia, media)
        XCTAssertEqual(mock.player.volume, volume)
        XCTAssertEqual(mock.player.audioEffects, originalEffects)
    }

    func testStereoOutputRetryClearsErrorAndCancellationRestoresIdle() async {
        let mock = MockBackend(scenario: .playingEpisode)
        let delayed = DelayedCuesPlayer(player: mock.player)
        let effects = AudioEffectsModel(backend: delayed)
        let failed = Task { await effects.testStereoOutput() }
        await delayed.waitForStereoRequest()
        delayed.finishStereo(BackendOperationError.unsupported("Stereo output test"))
        await failed.value
        XCTAssertNotNil(effects.testOutputError)
        let retry = Task { await effects.testStereoOutput() }
        await delayed.waitForStereoRequest()
        XCTAssertNil(effects.testOutputError)
        retry.cancel()
        delayed.finishStereo(CancellationError())
        await retry.value
        XCTAssertFalse(effects.isTestingOutput)
        XCTAssertNil(effects.testOutputError, "Cancellation is not an output device failure.")
    }

    func testMockStereoOutputRecordsActionWithoutChangingPlayback() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        let media = mock.player.currentMedia
        let state = mock.player.state
        let volume = mock.player.volume
        let effects = mock.player.audioEffects
        try await mock.player.testStereoOutput()
        XCTAssertEqual(mock.player.commandLog.last, "testStereoOutput")
        XCTAssertEqual(mock.player.currentMedia, media)
        XCTAssertEqual(mock.player.state, state)
        XCTAssertEqual(mock.player.volume, volume)
        XCTAssertEqual(mock.player.audioEffects, effects)
    }
}

/// Only the asynchronous cue response is delayed. All state and events use the real mock player.
@MainActor
private final class DelayedCuesPlayer: PlayerBackend {
    let player: MockPlayer
    private var pending: CheckedContinuation<[SubtitleCue], Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var pendingStereo: CheckedContinuation<Void, any Error>?
    private var waitingStereo: CheckedContinuation<Void, Never>?
    private(set) var stereoRequests = 0
    init(player: MockPlayer) { self.player = player }
    func subtitleCues(trackID: String) async -> [SubtitleCue] {
        await withCheckedContinuation { continuation in
            pending = continuation
            waiting?.resume()
            waiting = nil
        }
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func finish(_ cues: [SubtitleCue]) {
        pending?.resume(returning: cues)
        pending = nil
    }
    func testStereoOutput() async throws {
        stereoRequests += 1
        try await withCheckedThrowingContinuation { continuation in
            pendingStereo = continuation
            waitingStereo?.resume()
            waitingStereo = nil
        }
    }
    func waitForStereoRequest() async {
        if pendingStereo != nil { return }
        await withCheckedContinuation { waitingStereo = $0 }
    }
    func finishStereo(_ error: (any Error)? = nil) {
        if let error { pendingStereo?.resume(throwing: error) }
        else { pendingStereo?.resume() }
        pendingStereo = nil
    }
    var state: PlayerState { player.state }
    var currentMedia: MediaItem? { player.currentMedia }
    var capabilities: PlaybackCapabilities { player.capabilities }
    var rate: Double { player.rate }
    var volume: Double { player.volume }
    var isMuted: Bool { player.isMuted }
    var bufferingProgress: Double { player.bufferingProgress }
    var errorMessage: String? { player.errorMessage }
    func tracks(of kind: TrackKind) -> [Track] { player.tracks(of: kind) }
    var audioDevices: [AudioDevice] { player.audioDevices }
    var currentAudioDeviceID: String? { player.currentAudioDeviceID }
    var audioDelay: MediaTime { player.audioDelay }
    var subtitleDelay: MediaTime { player.subtitleDelay }
    var subtitleFPS: Double { player.subtitleFPS }
    var subtitleDurationFactor: Double { player.subtitleDurationFactor }
    var subtitleTextScale: Int { player.subtitleTextScale }
    var subtitleStyle: SubtitleStyle { player.subtitleStyle }
    var trackDefaults: TrackDefaults { player.trackDefaults }
    var titles: [MediaTitle] { player.titles }
    var selectedTitleIndex: Int? { player.selectedTitleIndex }
    var chapters: [Chapter] { player.chapters }
    var selectedChapterIndex: Int? { player.selectedChapterIndex }
    var programs: [MediaProgram] { player.programs }
    var abLoop: ABLoop { player.abLoop }
    var isRecording: Bool { player.isRecording }
    var isFullscreen: Bool { player.isFullscreen }
    var videoEffects: VideoEffects { player.videoEffects }
    var audioEffects: AudioEffects { player.audioEffects }
    var audioVisualization: AudioVisualization { player.audioVisualization }
    var restorePrompt: RestorePrompt? { player.restorePrompt }
    var statistics: MediaStatistics? { player.statistics }
    var teletext: TeletextState { player.teletext }
    var isPictureInPicture: Bool { player.isPictureInPicture }
    func play() { player.play() }
    func pause() { player.pause() }
    func togglePause() { player.togglePause() }
    func stop() { player.stop() }
    func seek(to time: MediaTime, precision: SeekPrecision) { player.seek(to: time, precision: precision) }
    func seek(toPosition position: Double, precision: SeekPrecision) { player.seek(toPosition: position, precision: precision) }
    func jump(by offset: MediaTime) { player.jump(by: offset) }
    func nextFrame() { player.nextFrame() }
    func setRate(_ rate: Double) { player.setRate(rate) }
    func setVolume(_ volume: Double) { player.setVolume(volume) }
    func setMuted(_ muted: Bool) { player.setMuted(muted) }
    func selectTrack(id: String, exclusive: Bool) { player.selectTrack(id: id, exclusive: exclusive) }
    func unselectTrack(id: String) { player.unselectTrack(id: id) }
    func unselectTracks(of kind: TrackKind) { player.unselectTracks(of: kind) }
    func addExternalTrack(url: URL, kind: TrackKind, select: Bool) { player.addExternalTrack(url: url, kind: kind, select: select) }
    func selectAudioDevice(id: String) { player.selectAudioDevice(id: id) }
    func refreshAudioDevices() { player.refreshAudioDevices() }
    func setAudioDelay(_ delay: MediaTime) { player.setAudioDelay(delay) }
    func setSubtitleDelay(_ delay: MediaTime) { player.setSubtitleDelay(delay) }
    func setSubtitleFPS(_ fps: Double) { player.setSubtitleFPS(fps) }
    func setSubtitleDurationFactor(_ factor: Double) { player.setSubtitleDurationFactor(factor) }
    func setSubtitleTextScale(_ percent: Int) { player.setSubtitleTextScale(percent) }
    func setSubtitleStyle(_ style: SubtitleStyle) { player.setSubtitleStyle(style) }
    func setTrackDefaults(_ defaults: TrackDefaults) { player.setTrackDefaults(defaults) }
    func setSubtitleSafeInset(points: Double, backingScale: Double) { player.setSubtitleSafeInset(points: points, backingScale: backingScale) }
    func selectTitle(index: Int) { player.selectTitle(index: index) }
    func selectChapter(index: Int) { player.selectChapter(index: index) }
    func selectProgram(id: Int) { player.selectProgram(id: id) }
    func toggleABLoop() { player.toggleABLoop() }
    func setRecording(_ enabled: Bool) { player.setRecording(enabled) }
    func takeSnapshot() { player.takeSnapshot() }
    func setFullscreen(_ fullscreen: Bool) { player.setFullscreen(fullscreen) }
    func setVideoEffects(_ effects: VideoEffects) { player.setVideoEffects(effects) }
    func setAudioEffects(_ effects: AudioEffects) { player.setAudioEffects(effects) }
    func setAudioVisualization(_ visualization: AudioVisualization) { player.setAudioVisualization(visualization) }
    func answerRestorePrompt(resume: Bool) { player.answerRestorePrompt(resume: resume) }
    func setTeletextEnabled(_ enabled: Bool) { player.setTeletextEnabled(enabled) }
    func selectTeletextPage(_ page: Int) { player.selectTeletextPage(page) }
    func setTeletextTransparent(_ transparent: Bool) { player.setTeletextTransparent(transparent) }
    func setPictureInPicture(_ active: Bool) { player.setPictureInPicture(active) }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (PlayerEvent) -> Void) { player.addListener(owner, handler: handler) }
}
