import Foundation
import MXRCore
import QuartzCore

/// Scripted player and clock. With ``MockBackend/ClockMode/realtime`` time advances while playing
/// (250 ms ticks, like VLC's timer); with `.frozen` it only moves on seeks (deterministic snapshots).
@MainActor
public final class MockPlayer: PlayerBackend, PlaybackClockSource {
    // PlayerBackend state
    public private(set) var state: PlayerState = .stopped
    public private(set) var currentMedia: MediaItem?
    public private(set) var capabilities: PlaybackCapabilities = []
    public private(set) var rate: Double = 1
    public private(set) var volume: Double = 1
    public private(set) var isMuted = false
    public private(set) var bufferingProgress: Double = 1
    public private(set) var errorMessage: String?
    public private(set) var audioDevices: [AudioDevice] = [AudioDevice(id: "speakers", name: "Speakers"), AudioDevice(id: "headphones", name: "Headphones")]
    public private(set) var currentAudioDeviceID: String? = "headphones"
    public private(set) var audioDelay: MediaTime = .zero
    public private(set) var subtitleDelay: MediaTime = .zero
    public private(set) var subtitleFPS: Double = 0
    public private(set) var subtitleDurationFactor: Double = 0
    public private(set) var subtitleTextScale = 100
    public private(set) var subtitleStyle = SubtitleStyle.default
    /// The last subtitle safe inset, in output pixels (layout only: no event).
    public private(set) var subtitleSafeInsetPixels = 0
    public private(set) var trackDefaults = TrackDefaults(audioTrack: 1, audioLanguage: "English", subtitleTrack: 1, subtitleLanguage: "English")
    public private(set) var titles: [MediaTitle] = []
    public private(set) var selectedTitleIndex: Int?
    public private(set) var chapters: [Chapter] = []
    public private(set) var selectedChapterIndex: Int?
    public private(set) var programs: [MediaProgram] = []
    public private(set) var abLoop: ABLoop = .off
    public private(set) var isRecording = false
    public private(set) var isFullscreen = false
    public private(set) var videoEffects = VideoEffects.default
    public private(set) var audioEffects = AudioEffects.default
    public private(set) var audioVisualization = AudioVisualization.disabled
    public private(set) var restorePrompt: RestorePrompt?
    public private(set) var statistics: MediaStatistics?

    /// Current media time (the mock's source of truth for the clock).
    public private(set) var time: MediaTime = .zero
    /// Commands received, newest last (for tests: "seek(00:01:00)", "play", …).
    public private(set) var commandLog: [String] = []

    /// Called when the media reaches its end (the queue advances).
    var onEndReached: (@MainActor () -> Void)?

    private var tracks: [TrackKind: [Track]] = [:]
    private var subtitleCueFixture: [SubtitleCue]?
    private let clockMode: MockBackend.ClockMode
    private var hostTimeAtTime: CFTimeInterval = 0
    private var tickTask: Task<Void, Never>?
    private let playerEvents = EventChannel<PlayerEvent>()
    private let clockEvents = EventChannel<ClockEvent>()
    private let library: () -> MockDatabase

    init(clockMode: MockBackend.ClockMode, library: @escaping () -> MockDatabase) {
        self.clockMode = clockMode
        self.library = library
    }

    // MARK: Loading (used by the queue and scenarios)

    /// Loads `media` at `start` in `state`, like the playlist starting an item (nil stops).
    public func load(_ media: MediaItem?, at start: MediaTime = .zero, state newState: PlayerState = .playing) {
        stopTicking()
        currentMedia = media
        time = start
        abLoop = .off
        restorePrompt = nil
        errorMessage = nil
        guard let media else {
            state = .stopped
            capabilities = []
            tracks = [:]
            titles = []
            chapters = []
            selectedChapterIndex = nil
            selectedTitleIndex = nil
            programs = []
            statistics = nil
            sendAll()
            clockEvents.send(.reset)
            return
        }
        capabilities = media.kind == .stream ? [.pause] : .file
        tracks = Self.tracks(for: media)
        let db = library()
        chapters = db.chapters[media.id] ?? []
        titles = [MediaTitle(index: 0, name: media.displayTitle, length: media.duration ?? .zero, chapters: chapters)]
        selectedTitleIndex = 0
        programs = []
        updateSelectedChapter()
        statistics = media.kind == .video
            ? MediaStatistics(inputBitrate: 1_450, demuxBitrate: 1_380, decodedVideoBlocks: 3_120, displayedPictures: 3_118,
                              lostPictures: 0, decodedAudioBlocks: 2_540, playedAudioBuffers: 2_540, lostAudioBuffers: 0)
            : nil
        state = newState
        sendAll()
        hostTimeAtTime = CACurrentMediaTime()
        clockEvents.send(.updated)
        startTickingIfNeeded()
    }

    /// Replaces the current media's metadata (library changes such as favorite or progress).
    func updateCurrentMedia(_ media: MediaItem) {
        guard currentMedia?.id == media.id else { return }
        currentMedia = media
        playerEvents.send(.metadata)
    }

    /// Shows the "continue watching" prompt for the current media (S12).
    public func askRestore(at time: MediaTime) {
        guard let media = currentMedia else { return }
        restorePrompt = RestorePrompt(mediaID: media.id, time: time)
        playerEvents.send(.restorePrompt)
    }

    /// Sets the volume without OSD.
    public func configureVolume(_ volume: Double) {
        self.volume = volume
        playerEvents.send(.volume)
    }

    // MARK: Tracks of a media

    static func tracks(for media: MediaItem) -> [TrackKind: [Track]] {
        switch media.kind {
        case .audio:
            return [.audio: [Track(id: "audio/0", kind: .audio, name: "Track 1", language: "English", codec: "MPEG Audio layer 3", isSelected: true)],
                    .video: [], .subtitle: []]
        case .stream:
            return [.audio: [Track(id: "audio/0", kind: .audio, name: "Track 1", codec: "AAC", isSelected: true)],
                    .video: [Track(id: "video/0", kind: .video, name: "Track 1", codec: "H.264", isSelected: true, videoSize: CGSize(width: 1280, height: 720))],
                    .subtitle: []]
        default:
            let size = media.videoSize ?? CGSize(width: 1920, height: 1080)
            var subtitles = [
                Track(id: "spu/2", kind: .subtitle, name: "English", language: "English", codec: "SubRip", isSelected: true),
                Track(id: "spu/3", kind: .subtitle, name: "Japanese", language: "Japanese", codec: "SubRip"),
            ]
            if media.episode?.showName == "The Wand" {
                subtitles.append(Track(id: "spu/ext-1", kind: .subtitle, name: "The_Wand_S01_EN.srt", language: "English", codec: "SubRip",
                                       isExternal: true, sourceURL: URL(fileURLWithPath: "/Users/Shared/Media/Videos/Shows/The Wand/The_Wand_S01_EN.srt")))
            }
            return [
                .video: [Track(id: "video/0", kind: .video, name: "Track 1", codec: size.width > 1920 ? "HEVC" : "H.264", isSelected: true, videoSize: size)],
                .audio: [
                    Track(id: "audio/0", kind: .audio, name: "English", language: "English", codec: "AAC"),
                    Track(id: "audio/1", kind: .audio, name: "Japanese", language: "Japanese", codec: "AAC", isSelected: true),
                ],
                .subtitle: subtitles,
            ]
        }
    }

    // MARK: PlayerBackend

    public func tracks(of kind: TrackKind) -> [Track] { tracks[kind] ?? [] }

    public func play() {
        log("play")
        guard currentMedia != nil else { return }
        setState(.playing)
    }

    public func pause() {
        log("pause")
        guard currentMedia != nil, state == .playing || state == .started else { return }
        setState(.paused)
    }

    public func togglePause() {
        if state == .paused { play() } else { pause() }
    }

    public func stop() {
        log("stop")
        load(nil)
    }

    public func seek(to time: MediaTime, precision: SeekPrecision) {
        log("seek(\(time.formatted(.hoursMinutesSeconds)))")
        setTime(time)
    }

    public func seek(toPosition position: Double, precision: SeekPrecision) {
        guard let length = currentMedia?.duration else { return }
        seek(to: length * position, precision: precision)
    }

    public func jump(by offset: MediaTime) {
        log("jump(\(offset.seconds))")
        setTime(time + offset)
    }

    public func nextFrame() {
        log("nextFrame")
        if state == .playing { setState(.paused) }
        setTime(time + .milliseconds(41))
    }

    public func setRate(_ rate: Double) {
        log("rate(\(rate))")
        rebaseTime()
        self.rate = rate
        playerEvents.send(.rate)
        clockEvents.send(.updated)
    }

    public func setVolume(_ volume: Double) {
        self.volume = min(max(volume, 0), 3)
        playerEvents.send(.volume)
    }

    public func setMuted(_ muted: Bool) {
        isMuted = muted
        playerEvents.send(.volume)
    }

    /// The window shows the PiP placeholder (S01.Window/pip, D042); the mock has no PiP window.
    public private(set) var isPictureInPicture = false
    public func setPictureInPicture(_ active: Bool) {
        isPictureInPicture = active
        playerEvents.send(.pictureInPicture)
    }

    public func selectTrack(id: String, exclusive: Bool) {
        log("selectTrack(\(id))")
        guard let kind = tracks.first(where: { $0.value.contains { $0.id == id } })?.key else { return }
        tracks[kind] = tracks[kind]?.map { track in
            var track = track
            if track.id == id { track.isSelected = true } else if exclusive { track.isSelected = false }
            return track
        }
        playerEvents.send(.tracks(kind))
    }

    public func unselectTrack(id: String) {
        guard let kind = tracks.first(where: { $0.value.contains { $0.id == id } })?.key else { return }
        tracks[kind] = tracks[kind]?.map { track in
            var track = track
            if track.id == id { track.isSelected = false }
            return track
        }
        playerEvents.send(.tracks(kind))
    }

    public func unselectTracks(of kind: TrackKind) {
        log("unselectTracks(\(kind.rawValue))")
        tracks[kind] = tracks[kind]?.map { track in
            var track = track
            track.isSelected = false
            return track
        }
        playerEvents.send(.tracks(kind))
    }

    public func addExternalTrack(url: URL, kind: TrackKind, select: Bool) {
        log("addExternalTrack(\(url.lastPathComponent))")
        let id = "\(kind == .subtitle ? "spu" : kind.rawValue)/ext-\((tracks[kind]?.count ?? 0) + 1)"
        var list = tracks[kind] ?? []
        if select { list = list.map { var t = $0; t.isSelected = false; return t } }
        list.append(Track(id: id, kind: kind, name: url.lastPathComponent, language: SubtitleMatcher.language(in: url.lastPathComponent),
                          isSelected: select, isExternal: true, sourceURL: url))
        tracks[kind] = list
        playerEvents.send(.tracks(kind))
    }

    public func selectAudioDevice(id: String) {
        log("selectAudioDevice(\(id))")
        currentAudioDeviceID = id
        playerEvents.send(.audioDevices)
    }

    public func refreshAudioDevices() {
        log("refreshAudioDevices")
        playerEvents.send(.audioDevices)
    }

    public func setAudioDelay(_ delay: MediaTime) {
        audioDelay = delay
        playerEvents.send(.synchronization)
    }

    public func setSubtitleDelay(_ delay: MediaTime) {
        subtitleDelay = delay
        playerEvents.send(.synchronization)
    }

    public func setSubtitleFPS(_ fps: Double) {
        subtitleFPS = fps
        playerEvents.send(.synchronization)
    }

    public func setSubtitleDurationFactor(_ factor: Double) {
        subtitleDurationFactor = factor
        playerEvents.send(.synchronization)
    }

    public func setSubtitleTextScale(_ percent: Int) {
        subtitleTextScale = percent
        playerEvents.send(.synchronization)
    }

    public func setSubtitleStyle(_ style: SubtitleStyle) {
        subtitleStyle = style
        playerEvents.send(.subtitleStyle)
    }

    public func setSubtitleSafeInset(points: Double, backingScale: Double) {
        subtitleSafeInsetPixels = Int((max(0, points) * (backingScale > 0 ? backingScale : 1)).rounded())
    }

    public func setTrackDefaults(_ defaults: TrackDefaults) {
        trackDefaults = defaults
        playerEvents.send(.trackDefaults)
    }

    public func subtitleCues(trackID: String) async -> [SubtitleCue] {
        if let subtitleCueFixture { return subtitleCueFixture }
        guard let media = currentMedia, let length = media.duration else { return [] }
        return mockSubtitleCues(seed: media.id + trackID, length: length)
    }

    /// Exact cue data for a gallery/test scene. Passing nil restores the generated mock source.
    public func setSubtitleCues(_ cues: [SubtitleCue]?) {
        subtitleCueFixture = cues
    }

    public func selectTitle(index: Int) {
        guard titles.indices.contains(index) else { return }
        selectedTitleIndex = index
        playerEvents.send(.titles)
    }

    public func selectChapter(index: Int) {
        guard chapters.indices.contains(index) else { return }
        log("selectChapter(\(index))")
        setTime(chapters[index].time)
    }

    public func selectProgram(id: Int) {
        programs = programs.map { var p = $0; p.isSelected = p.id == id; return p }
        playerEvents.send(.programs)
    }

    public func toggleABLoop() {
        switch abLoop {
        case .off: abLoop = .pointA(time)
        case .pointA(let a): abLoop = .looping(a: a, b: max(time, a + .seconds(1)))
        case .looping: abLoop = .off
        }
        playerEvents.send(.abLoop)
    }

    public func setRecording(_ enabled: Bool) {
        isRecording = enabled
        playerEvents.send(.recording)
    }

    public func takeSnapshot() {
        log("snapshot")
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vlcsnap-mock.png")
        playerEvents.send(.snapshotTaken(url))
    }

    public func setFullscreen(_ fullscreen: Bool) {
        isFullscreen = fullscreen
        playerEvents.send(.fullscreen)
    }

    public func setVideoEffects(_ effects: VideoEffects) {
        videoEffects = effects
        playerEvents.send(.videoEffects)
    }

    public func setAudioEffects(_ effects: AudioEffects) {
        audioEffects = effects
        playerEvents.send(.audioEffects)
    }

    /// Deterministic gallery action; the mock never plays audio on a physical output device.
    public func testStereoOutput() async throws { log("testStereoOutput") }

    public func setAudioVisualization(_ visualization: AudioVisualization) {
        audioVisualization = visualization
        playerEvents.send(.audioVisualization)
    }

    public func answerRestorePrompt(resume: Bool) {
        log("answerRestorePrompt(\(resume))")
        let prompt = restorePrompt
        restorePrompt = nil
        playerEvents.send(.restorePrompt)
        if resume, let prompt { setTime(prompt.time) }
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (PlayerEvent) -> Void) {
        playerEvents.add(owner, handler: handler)
    }

    // MARK: PlaybackClockSource

    public var timerPoint: TimerPoint? {
        guard let media = currentMedia else { return nil }
        let length = media.duration ?? .zero
        let position = length > .zero ? min(max(time.seconds / length.seconds, 0), 1) : 0
        let running = clockMode == .realtime && state == .playing
        return TimerPoint(time: time, length: length, position: position, rate: rate, hostTime: running ? hostTimeAtTime : nil)
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void) {
        clockEvents.add(owner, handler: handler)
    }

    // MARK: Private

    private func log(_ command: String) { commandLog.append(command) }

    private func setState(_ newState: PlayerState) {
        rebaseTime()
        state = newState
        playerEvents.send(.state)
        clockEvents.send(newState == .playing ? .updated : .discontinuity)
        if newState == .playing { startTickingIfNeeded() } else { stopTicking() }
    }

    private func setTime(_ newTime: MediaTime) {
        guard let media = currentMedia else { return }
        var clamped = max(.zero, newTime)
        if let length = media.duration { clamped = min(clamped, length) }
        time = clamped
        hostTimeAtTime = CACurrentMediaTime()
        updateSelectedChapter()
        clockEvents.send(.updated)
    }

    /// Folds the elapsed real time into `time` before a rate/state change.
    private func rebaseTime() {
        guard clockMode == .realtime, state == .playing else {
            hostTimeAtTime = CACurrentMediaTime()
            return
        }
        let now = CACurrentMediaTime()
        time = time + .seconds((now - hostTimeAtTime) * rate)
        hostTimeAtTime = now
    }

    private func updateSelectedChapter() {
        let index = chapters.lastIndex { $0.time <= time }
        if index != selectedChapterIndex {
            selectedChapterIndex = index
            playerEvents.send(.titles)
        }
    }

    private func sendAll() {
        for event: PlayerEvent in [.media, .state, .capabilities, .rate, .volume, .buffering, .error, .tracks(.video), .tracks(.audio),
                                   .tracks(.subtitle), .titles, .programs, .abLoop, .restorePrompt, .statistics] {
            playerEvents.send(event)
        }
    }

    private func startTickingIfNeeded() {
        guard clockMode == .realtime, state == .playing, tickTask == nil else { return }
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func tick() {
        guard state == .playing, let media = currentMedia else { return }
        rebaseTime()
        if case .looping(let a, let b) = abLoop, time >= b { time = a }
        updateSelectedChapter()
        if let length = media.duration, time >= length {
            time = length
            clockEvents.send(.updated)
            stopTicking()
            if let onEndReached { onEndReached() } else { load(nil) }
            return
        }
        clockEvents.send(.updated)
    }
}
