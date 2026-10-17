import Foundation
import Observation

/// Player state for the control bar, top bar and playback sidebar (S01, S04, S05, S12, S17).
///
/// Holds no time (see ``PlaybackClock``). Tracks live in ``TracksModel``, effects in
/// ``VideoEffectsModel`` / ``AudioEffectsModel``, prev/next in ``QueueModel``.
@MainActor
@Observable
public final class PlayerModel {
    public private(set) var state: PlayerState = .stopped
    /// The current media, nil when nothing is loaded.
    public private(set) var media: MediaItem?
    public private(set) var capabilities: PlaybackCapabilities = []
    /// Rate, 1 = normal.
    public private(set) var rate: Double = 1
    /// VLC volume scale, where 1 is 100%.
    public private(set) var volume: Double = 1
    /// Upper bound from the player's volume preference.
    public private(set) var maximumVolume: Double = 2
    public private(set) var isMuted: Bool = false
    /// Buffering progress 0...1 (1 = not buffering).
    public private(set) var bufferingProgress: Double = 1
    public private(set) var errorMessage: String?
    public private(set) var isRecording: Bool = false
    public private(set) var abLoop: ABLoop = .off
    /// Whether the engine wants fullscreen. The window controller observes this and toggles native fullscreen.
    public private(set) var isFullscreen: Bool = false
    public private(set) var audioVisualization: AudioVisualization = .disabled
    /// Non-nil while the "continue watching" toast should show (S12).
    public private(set) var restorePrompt: RestorePrompt?
    public private(set) var statistics: MediaStatistics?
    /// Teletext of the current media.
    public private(set) var teletext: TeletextState = .unavailable
    /// True while the video is in Picture in Picture.
    public private(set) var isPictureInPicture = false
    public private(set) var sleepTimer: SleepTimer = .off
    /// When the sleep timer fires (nil when off or `.endOfItem`).
    public private(set) var sleepDeadline: Date?
    /// The last snapshot file written.
    public private(set) var lastSnapshotURL: URL?

    /// Time before the restore prompt dismisses itself ("I have like five seconds to respond");
    /// nil keeps it until answered (deterministic gallery snapshots).
    @ObservationIgnored public var restorePromptTimeout: Duration?
    /// Volume increment for scroll and keys, where 0.01 means one percentage point.
    public var volumeStep: Double = 0.05
    @ObservationIgnored private var allowsRestorePrompt = true

    @ObservationIgnored public let backend: any PlayerBackend
    @ObservationIgnored private var restoreTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    /// Set by ``AppModel``: asks the queue to pause at the end of the current item (true) or to continue (false).
    @ObservationIgnored var endOfItemHook: (@MainActor (Bool) -> Void)?

    /// - Parameter restorePromptTimeout: see ``restorePromptTimeout``.
    public init(backend: any PlayerBackend, restorePromptTimeout: Duration? = .seconds(5)) {
        self.backend = backend
        self.restorePromptTimeout = restorePromptTimeout
        backend.addListener(self) { [weak self] event in
            self?.handle(event)
        }
        reloadAll()
        // A prompt that already exists (media restored at launch) must time out too.
        if restorePrompt != nil { updateRestorePrompt() }
    }

    // MARK: Derived

    /// True when the play button should show "pause" (playing or opening).
    public var isPlaying: Bool { state == .playing || state == .started }
    /// True when nothing is loaded or playback stopped.
    public var isStopped: Bool { state == .stopped || media == nil }
    public var canSeek: Bool { capabilities.contains(.seek) }
    public var canPause: Bool { capabilities.contains(.pause) }
    public var canChangeRate: Bool { capabilities.contains(.changeRate) }
    /// True for audio-only media (music now-playing layout, S34).
    public var isAudioOnly: Bool { media?.kind == .audio }
    /// The centered top-bar title: the media's display title, or "VLC Media Player" when idle.
    public var windowTitle: String { media?.displayTitle ?? "VLC Media Player" }
    /// Volume as a whole percentage (volume tooltip "100 %").
    public var volumePercent: Int { Int((volume * 100).rounded()) }
    public var isBuffering: Bool { bufferingProgress < 1 && state == .started }

    // MARK: Transport

    public func play() { backend.play() }
    public func pause() { backend.pause() }
    /// The play/pause button and Space.
    public func togglePlayPause() {
        if isStopped { backend.play() } else { backend.togglePause() }
    }
    public func stop() { backend.stop() }
    /// Seeks precisely (click, typed time, chapter). Use `precision: .fast` while dragging.
    public func seek(to time: MediaTime, precision: SeekPrecision = .precise) {
        guard canSeek else { return }
        backend.seek(to: max(.zero, time), precision: precision)
    }
    /// Seeks to a fraction 0...1 of the length.
    public func seek(toPosition position: Double, precision: SeekPrecision = .precise) {
        guard canSeek else { return }
        backend.seek(toPosition: min(max(position, 0), 1), precision: precision)
    }
    /// Skips by `offset` (±10 s / ±15 s buttons).
    public func jump(by offset: MediaTime) {
        guard canSeek else { return }
        backend.jump(by: offset)
    }
    public func nextFrame() { backend.nextFrame() }

    // MARK: Rate and volume

    /// Sets the rate, clamped to 0.25...4.
    public func setRate(_ rate: Double) {
        guard canChangeRate || rate == 1 else { return }
        backend.setRate(min(max(rate, 0.25), 4))
    }
    /// Sets the volume within the configured range, unmuting when raised above zero.
    public func setVolume(_ volume: Double) {
        guard volume.isFinite else { return }
        let clamped = min(max(volume, 0), maximumVolume)
        backend.setVolume(clamped)
        if isMuted && clamped > 0 { backend.setMuted(false) }
    }
    func configurePreferences(maximumVolume: Double, volumeStep: Double, allowsRestorePrompt: Bool) {
        self.maximumVolume = maximumVolume
        self.volumeStep = volumeStep
        if volume > maximumVolume { setVolume(maximumVolume) }
        if self.allowsRestorePrompt != allowsRestorePrompt {
            self.allowsRestorePrompt = allowsRestorePrompt
            updateRestorePrompt()
        }
    }
    public func adjustVolume(steps: Int) { setVolume(volume + Double(steps) * volumeStep) }
    public func toggleMute() { backend.setMuted(!isMuted) }

    // MARK: Misc

    public func toggleRecording() { backend.setRecording(!isRecording) }
    public func takeSnapshot() { backend.takeSnapshot() }
    public func toggleABLoop() { backend.toggleABLoop() }
    /// Reports a window-initiated fullscreen change to the engine.
    public func setFullscreen(_ fullscreen: Bool) { backend.setFullscreen(fullscreen) }
    public func setAudioVisualization(_ visualization: AudioVisualization) { backend.setAudioVisualization(visualization) }
    /// Starts or stops Picture in Picture (only when `app.capabilities.pictureInPicture` allows it).
    public func setPictureInPicture(_ active: Bool) { backend.setPictureInPicture(active) }

    // MARK: Teletext

    public func setTeletextEnabled(_ enabled: Bool) { backend.setTeletextEnabled(enabled) }
    /// Page 100...899.
    public func selectTeletextPage(_ page: Int) { backend.selectTeletextPage(min(max(page, 100), 899)) }
    public func setTeletextTransparent(_ transparent: Bool) { backend.setTeletextTransparent(transparent) }

    /// "Continue Watching": resume at the saved time.
    public func resumePlayback() {
        restoreTimeoutTask?.cancel()
        backend.answerRestorePrompt(resume: true)
    }
    /// ✕ on the toast (or timeout): keep playing from the start.
    public func dismissRestorePrompt() {
        restoreTimeoutTask?.cancel()
        backend.answerRestorePrompt(resume: false)
    }
    /// The pointer is over the continue-watching toast: its timeout waits until the pointer leaves
    /// and then starts over (BB-10).
    public func holdRestorePrompt(_ held: Bool) {
        guard restorePrompt != nil else { return }
        if held { restoreTimeoutTask?.cancel(); restoreTimeoutTask = nil } else { updateRestorePrompt() }
    }

    /// Starts, changes or cancels the sleep timer. When it fires, playback pauses.
    public func setSleepTimer(_ timer: SleepTimer) {
        sleepTask?.cancel()
        sleepTask = nil
        let wasEndOfItem = sleepTimer == .endOfItem
        sleepTimer = timer
        if wasEndOfItem != (timer == .endOfItem) { endOfItemHook?(timer == .endOfItem) }
        guard let interval = timer.interval else {
            sleepDeadline = nil
            return
        }
        let seconds = Double(interval.components.seconds)
        sleepDeadline = Date().addingTimeInterval(seconds)
        sleepTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            self.backend.pause()
            self.sleepTimer = .off
            self.sleepDeadline = nil
        }
    }

    // MARK: Events

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .state:
            state = backend.state
            if sleepTimer == .endOfItem, state == .paused || state == .stopped {
                sleepTimer = .off
                endOfItemHook?(false)
            }
        case .media, .metadata:
            media = backend.currentMedia
        case .capabilities: capabilities = backend.capabilities
        case .rate: rate = backend.rate
        case .volume:
            volume = backend.volume
            isMuted = backend.isMuted
        case .buffering: bufferingProgress = backend.bufferingProgress
        case .error: errorMessage = backend.errorMessage
        case .recording: isRecording = backend.isRecording
        case .abLoop: abLoop = backend.abLoop
        case .fullscreen: isFullscreen = backend.isFullscreen
        case .audioVisualization: audioVisualization = backend.audioVisualization
        case .restorePrompt: updateRestorePrompt()
        case .statistics: statistics = backend.statistics
        case .teletext: teletext = backend.teletext
        case .pictureInPicture: isPictureInPicture = backend.isPictureInPicture
        case .snapshotTaken(let url): lastSnapshotURL = url
        case .tracks, .audioDevices, .synchronization, .subtitleStyle, .trackDefaults, .titles, .programs, .videoEffects, .audioEffects:
            break
        }
    }

    private func updateRestorePrompt() {
        restoreTimeoutTask?.cancel()
        guard allowsRestorePrompt else {
            restorePrompt = nil
            if backend.restorePrompt != nil { backend.answerRestorePrompt(resume: false) }
            return
        }
        restorePrompt = backend.restorePrompt
        guard restorePrompt != nil, let timeout = restorePromptTimeout else { return }
        restoreTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, self.restorePrompt != nil else { return }
            self.dismissRestorePrompt()
        }
    }

    private func reloadAll() {
        state = backend.state
        media = backend.currentMedia
        capabilities = backend.capabilities
        rate = backend.rate
        volume = backend.volume
        isMuted = backend.isMuted
        bufferingProgress = backend.bufferingProgress
        errorMessage = backend.errorMessage
        isRecording = backend.isRecording
        abLoop = backend.abLoop
        isFullscreen = backend.isFullscreen
        audioVisualization = backend.audioVisualization
        statistics = backend.statistics
        teletext = backend.teletext
        isPictureInPicture = backend.isPictureInPicture
        restorePrompt = backend.restorePrompt
    }
}
