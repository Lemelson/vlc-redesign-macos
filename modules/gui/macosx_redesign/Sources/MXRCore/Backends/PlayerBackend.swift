import Foundation

/// Player change notifications. Payload-free: on an event, read the matching property of the backend.
public enum PlayerEvent: Sendable, Hashable {
    case state
    /// A different media is loaded (or none).
    case media
    /// The current media's metadata or library state changed (title, artwork, favorite, progress).
    case metadata
    case capabilities
    case rate
    /// Volume or mute.
    case volume
    case buffering
    case error
    /// Track list or selection of this kind changed.
    case tracks(TrackKind)
    /// Device list or current device.
    case audioDevices
    /// Audio delay, subtitle delay, subtitle FPS or duration factor.
    case synchronization
    case subtitleStyle
    case trackDefaults
    /// Titles or chapters list, or the selected title/chapter.
    case titles
    case programs
    case abLoop
    case recording
    /// The engine asks to enter or leave fullscreen (hotkey "f", `vlc_player_vout_SetFullscreen`).
    case fullscreen
    case videoEffects
    case audioEffects
    case audioVisualization
    case restorePrompt
    case statistics
    /// Teletext availability, page or transparency.
    case teletext
    /// Picture in Picture started or stopped.
    case pictureInPicture
    /// A snapshot was written to this file.
    case snapshotTaken(URL)
}

/// The player (`vlc_player_t` + its aout and vout). Everything the control bar, the track popover
/// and the playback sidebar need. All members are called on the main actor and must not block;
/// properties must be cheap to read (cached or read under the player lock).
///
/// **Read-your-writes:** after a setter returns, the matching property must already return the new
/// value (update the cache in the setter, or read it back from `vlc_player`), even though the change
/// event may arrive later through `dispatch_async`. Models build relative edits (delay nudges,
/// equalizer bands, style tweaks) on the property, so a stale value would drop quick edits.
@MainActor
public protocol PlayerBackend: AnyObject {
    // MARK: State
    var state: PlayerState { get }
    /// The current media, nil when stopped with nothing loaded.
    var currentMedia: MediaItem? { get }
    var capabilities: PlaybackCapabilities { get }
    /// Playback rate, 1 = normal (VLC range 0.25...4 from the UI).
    var rate: Double { get }
    /// Volume, 0...2 (0–200 %), `vlc_player_aout_GetVolume`.
    var volume: Double { get }
    var isMuted: Bool { get }
    /// Buffering progress 0...1; 1 when not buffering.
    var bufferingProgress: Double { get }
    /// A human-readable error for the current media, or nil.
    var errorMessage: String? { get }

    // MARK: Tracks and devices
    /// Tracks of `kind`, in VLC order.
    func tracks(of kind: TrackKind) -> [Track]
    var audioDevices: [AudioDevice] { get }
    var currentAudioDeviceID: String? { get }
    var audioDelay: MediaTime { get }
    var subtitleDelay: MediaTime { get }
    /// Subtitle speed in frames per second ("Subtitle Speed 1.000 fps"); 0 = media default.
    var subtitleFPS: Double { get }
    /// Subtitle duration factor ("Subtitle Duration Factor").
    var subtitleDurationFactor: Double { get }
    /// Relative subtitle text scale in percent, 10...500 (`vlc_player_SetSubtitleTextScale`).
    var subtitleTextScale: Int { get }
    var subtitleStyle: SubtitleStyle { get }
    var trackDefaults: TrackDefaults { get }

    // MARK: Structure
    var titles: [MediaTitle] { get }
    var selectedTitleIndex: Int? { get }
    /// Chapters of the selected title.
    var chapters: [Chapter] { get }
    var selectedChapterIndex: Int? { get }
    var programs: [MediaProgram] { get }

    // MARK: Misc state
    var abLoop: ABLoop { get }
    var isRecording: Bool { get }
    /// Whether the engine currently wants fullscreen (window chrome follows this).
    var isFullscreen: Bool { get }
    var videoEffects: VideoEffects { get }
    var audioEffects: AudioEffects { get }
    var audioVisualization: AudioVisualization { get }
    /// Non-nil while the engine asks whether to resume (S12).
    var restorePrompt: RestorePrompt? { get }
    /// Input statistics, refreshed about once per second while playing; nil when unavailable.
    var statistics: MediaStatistics? { get }
    /// Teletext of the current media (``TeletextState/unavailable`` when none).
    var teletext: TeletextState { get }
    /// True while the video is shown in Picture in Picture (ARCHITECTURE §3.5).
    var isPictureInPicture: Bool { get }

    // MARK: Transport
    func play()
    func pause()
    func togglePause()
    /// Stops playback (non-blocking; `vlc_player_Stop`).
    func stop()
    func seek(to time: MediaTime, precision: SeekPrecision)
    func seek(toPosition position: Double, precision: SeekPrecision)
    /// Relative seek (skip buttons, arrow keys).
    func jump(by offset: MediaTime)
    func nextFrame()
    func setRate(_ rate: Double)
    func setVolume(_ volume: Double)
    func setMuted(_ muted: Bool)

    // MARK: Tracks
    /// Selects a track. With `exclusive` (the default UI behavior) other tracks of the kind are unselected.
    func selectTrack(id: String, exclusive: Bool)
    func unselectTrack(id: String)
    /// Unselects every track of `kind` ("None").
    func unselectTracks(of kind: TrackKind)
    /// Adds an external file as a track (`vlc_player_AddAssociatedMedia`), optionally selecting it.
    func addExternalTrack(url: URL, kind: TrackKind, select: Bool)
    func selectAudioDevice(id: String)
    /// Re-enumerates audio devices (the refresh icon of "Output Device").
    func refreshAudioDevices()
    func setAudioDelay(_ delay: MediaTime)
    func setSubtitleDelay(_ delay: MediaTime)
    func setSubtitleFPS(_ fps: Double)
    func setSubtitleDurationFactor(_ factor: Double)
    func setSubtitleTextScale(_ percent: Int)
    func setSubtitleStyle(_ style: SubtitleStyle)
    func setTrackDefaults(_ defaults: TrackDefaults)
    /// Raises subtitles above the UI's overlays (the revealed fullscreen control bar, a panel over
    /// the bottom of the picture): `points` the overlays cover above the bottom edge of the video
    /// picture (see ``SubtitleSafeInset``), `backingScale` of the video view. Adds to the user's
    /// Subtitle Offset without changing it; not saved. Zero puts subtitles back.
    func setSubtitleSafeInset(points: Double, backingScale: Double)
    /// Cue times of a subtitle track for the timeline (S21). Empty when unsupported.
    func subtitleCues(trackID: String) async -> [SubtitleCue]

    // MARK: Structure
    func selectTitle(index: Int)
    func selectChapter(index: Int)
    func selectProgram(id: Int)

    // MARK: Misc commands
    /// Sets A, then B, then clears, like VLC's A-B button.
    func toggleABLoop()
    func setRecording(_ enabled: Bool)
    func takeSnapshot()
    /// Tells the engine about a fullscreen change made by the window (keeps vout state in sync).
    func setFullscreen(_ fullscreen: Bool)
    func setVideoEffects(_ effects: VideoEffects)
    func setAudioEffects(_ effects: AudioEffects)
    /// Plays a bounded left/right output test without changing the main player's media or volume.
    func testStereoOutput() async throws
    func setAudioVisualization(_ visualization: AudioVisualization)
    /// Answers the restore prompt: resume at the saved time, or start from the beginning.
    func answerRestorePrompt(resume: Bool)
    func setTeletextEnabled(_ enabled: Bool)
    /// Shows teletext page 100...899 (`vlc_player_SelectTeletextPage`).
    func selectTeletextPage(_ page: Int)
    func setTeletextTransparent(_ transparent: Bool)
    /// Asks the video output to enter or leave Picture in Picture; the result arrives as `.pictureInPicture`.
    func setPictureInPicture(_ active: Bool)

    /// Registers a listener for player events (see ``EventChannel``).
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (PlayerEvent) -> Void)
}

/// Transitional defaults so backends written before these members existed keep compiling.
/// Implement them for real (VLC: `vlc_player_*Teletext*`, the PiP controller of ARCHITECTURE §3.5).
extension PlayerBackend {
    public func testStereoOutput() async throws { throw BackendOperationError.unsupported("Stereo output test") }
    public var teletext: TeletextState { .unavailable }
    public var isPictureInPicture: Bool { false }
    public func setTeletextEnabled(_ enabled: Bool) {}
    public func selectTeletextPage(_ page: Int) {}
    public func setTeletextTransparent(_ transparent: Bool) {}
    public func setPictureInPicture(_ active: Bool) {}
}

/// One timing sample of the player (`struct vlc_player_timer_point`).
public struct TimerPoint: Hashable, Sendable {
    /// Media time at `hostTime`.
    public var time: MediaTime
    /// Media length; zero when unknown or live.
    public var length: MediaTime
    /// Position 0...1 at `hostTime`.
    public var position: Double
    /// Playback rate used for interpolation.
    public var rate: Double
    /// Host time (`CACurrentMediaTime()` base, seconds) at which `time` was valid.
    /// Nil means do not interpolate (paused, seeking, frozen mock clock).
    public var hostTime: CFTimeInterval?

    public init(time: MediaTime, length: MediaTime, position: Double, rate: Double, hostTime: CFTimeInterval?) {
        self.time = time
        self.length = length
        self.position = position
        self.rate = rate
        self.hostTime = hostTime
    }
}

/// Clock notifications.
public enum ClockEvent: Sendable, Hashable {
    /// A new timer point is available.
    case updated
    /// Interpolation must stop (pause, end of stream); the point is still valid.
    case discontinuity
    /// No media: the clock is cleared.
    case reset
}

/// The time source, kept separate from ``PlayerBackend`` so ticks do not invalidate `PlayerModel`
/// (ARCHITECTURE §2.3 rule 6). The VLC backend feeds it from `vlc_player_AddTimer` (250 ms), converting
/// `system_date` to the `CACurrentMediaTime()` base.
@MainActor
public protocol PlaybackClockSource: AnyObject {
    /// The latest point, nil when nothing is loaded.
    var timerPoint: TimerPoint? { get }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (ClockEvent) -> Void)
}

/// How far overlays cover the bottom of the video picture, for
/// ``PlayerBackend/setSubtitleSafeInset(points:backingScale:)``. VLC draws subtitles centred at
/// the bottom of the picture, so only overlays across the picture's horizontal centre hide them,
/// and letterbox bars below the picture already keep them clear of an overlay.
public enum SubtitleSafeInset {
    /// The picture of a `videoSize` video fitted into `bounds` (VLC's default "fit window").
    public static func fittedPicture(videoSize: CGSize, in bounds: CGRect) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// Points of `picture` covered from its bottom edge by `overlays` (same coordinate space,
    /// y growing downwards, like SwiftUI and flipped AppKit views).
    public static func points(picture: CGRect, overlays: [CGRect]) -> Double {
        guard !picture.isEmpty else { return 0 }
        let covered = overlays
            .filter { !$0.isEmpty && $0.minX <= picture.midX && $0.maxX >= picture.midX && $0.maxY > picture.minY }
            .map { picture.maxY - max($0.minY, picture.minY) }
            .max() ?? 0
        return Double(min(max(covered, 0), picture.height))
    }
}
