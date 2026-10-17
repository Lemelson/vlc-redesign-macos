import Foundation
import Observation

/// Tracks, output devices, synchronization and subtitle appearance: the track popover (S14–S16) and
/// the Defaults/Synchronization/Appearance sections of the sidebar Audio and Subtitles tabs (S19, S20).
@MainActor
@Observable
public final class TracksModel {
    public private(set) var videoTracks: [Track] = []
    public private(set) var audioTracks: [Track] = []
    public private(set) var subtitleTracks: [Track] = []
    public private(set) var audioDevices: [AudioDevice] = []
    public private(set) var currentAudioDeviceID: String?
    /// Positive = audio later.
    public private(set) var audioDelay: MediaTime = .zero
    /// Positive = subtitles later.
    public private(set) var subtitleDelay: MediaTime = .zero
    public private(set) var subtitleFPS: Double = 0
    public private(set) var subtitleDurationFactor: Double = 0
    /// 10...500 %.
    public private(set) var subtitleTextScale: Int = 100
    public private(set) var subtitleStyle: SubtitleStyle = .default
    public private(set) var trackDefaults = TrackDefaults()
    /// Cues of the selected subtitle track for the timeline (S21); load with ``loadSubtitleCues()``.
    public private(set) var subtitleCues: [SubtitleCue] = []

    /// Step of the timeline −/+ buttons and the subtitle-delay hotkeys (VLC: 50 ms).
    @ObservationIgnored public var delayStep: MediaTime = .milliseconds(50)
    @ObservationIgnored public let backend: any PlayerBackend
    @ObservationIgnored private var cuesTask: Task<Void, Never>?
    @ObservationIgnored private var cueGeneration = 0

    public init(backend: any PlayerBackend) {
        self.backend = backend
        backend.addListener(self) { [weak self] event in
            self?.handle(event)
        }
        for kind in TrackKind.allCases { reloadTracks(kind) }
        reloadDevices()
        reloadSync()
        subtitleStyle = backend.subtitleStyle
        trackDefaults = backend.trackDefaults
    }

    // MARK: Tracks

    /// Tracks of a kind.
    public func tracks(of kind: TrackKind) -> [Track] {
        switch kind {
        case .video: videoTracks
        case .audio: audioTracks
        case .subtitle: subtitleTracks
        }
    }
    /// Embedded tracks of a kind ("Embedded Tracks" section).
    public func embeddedTracks(of kind: TrackKind) -> [Track] { tracks(of: kind).filter { !$0.isExternal } }
    /// Tracks loaded from files ("External Tracks" section).
    public func externalTracks(of kind: TrackKind) -> [Track] { tracks(of: kind).filter(\.isExternal) }
    /// The selected track of a kind, nil = "None".
    public func selectedTrack(of kind: TrackKind) -> Track? { tracks(of: kind).first(where: \.isSelected) }
    /// True when no track of the kind is selected ("None" checked).
    public func isNoneSelected(_ kind: TrackKind) -> Bool { selectedTrack(of: kind) == nil }

    /// Selects a track (exclusive within its kind).
    public func select(_ track: Track) { backend.selectTrack(id: track.id, exclusive: true) }
    /// "None".
    public func selectNone(_ kind: TrackKind) { backend.unselectTracks(of: kind) }
    /// Cycles to the next track of a kind, including "None" (hotkeys V/B in the onboarding list).
    public func cycle(_ kind: TrackKind) {
        let list = tracks(of: kind)
        guard !list.isEmpty else { return }
        if let index = list.firstIndex(where: \.isSelected) {
            if index + 1 < list.count { select(list[index + 1]) } else { selectNone(kind) }
        } else {
            select(list[0])
        }
    }
    /// Loads a subtitle or audio file for the current media and selects it.
    public func addExternalTrack(url: URL, kind: TrackKind = .subtitle) {
        backend.addExternalTrack(url: url, kind: kind, select: true)
    }

    // MARK: Devices

    public var currentAudioDevice: AudioDevice? { audioDevices.first { $0.id == currentAudioDeviceID } }
    public func selectAudioDevice(_ device: AudioDevice) { backend.selectAudioDevice(id: device.id) }
    public func refreshAudioDevices() { backend.refreshAudioDevices() }

    // MARK: Synchronization

    // Setters re-read the backend right away (read-your-writes, see ``PlayerBackend``), so the UI does
    // not wait for the event, and relative edits start from the engine's value, not from this mirror:
    // two quick nudges made before the first event arrives both count.

    public func setAudioDelay(_ delay: MediaTime) {
        backend.setAudioDelay(delay)
        reloadSync()
    }
    public func setSubtitleDelay(_ delay: MediaTime) {
        backend.setSubtitleDelay(delay)
        reloadSync()
    }
    /// Timeline "+"/"−" (and the delay hotkeys): shifts the subtitle delay by `steps` × ``delayStep``.
    public func nudgeSubtitleDelay(steps: Int) { setSubtitleDelay(backend.subtitleDelay + delayStep * Double(steps)) }
    public func setSubtitleFPS(_ fps: Double) {
        backend.setSubtitleFPS(fps)
        reloadSync()
    }
    /// The sidebar's "Subtitle Speed" (804:1170). VLC's `sub-fps` only takes effect above 1 fps
    /// (src/input/input.c RequestSubRate), so 0 (unset) and 1 both mean "not overridden"; like VLC's
    /// Qt sync panel (extended_panels.cpp: 1…100 fps, reset to 1.000) the speed is shown from 1.
    public static let subtitleSpeedRange: ClosedRange<Double> = 1...100
    public var subtitleSpeed: Double { min(max(subtitleFPS, Self.subtitleSpeedRange.lowerBound), Self.subtitleSpeedRange.upperBound) }
    public func setSubtitleSpeed(_ fps: Double) {
        setSubtitleFPS(min(max(fps, Self.subtitleSpeedRange.lowerBound), Self.subtitleSpeedRange.upperBound))
    }
    public func setSubtitleDurationFactor(_ factor: Double) {
        backend.setSubtitleDurationFactor(factor)
        reloadSync()
    }
    public func setSubtitleTextScale(_ percent: Int) {
        backend.setSubtitleTextScale(min(max(percent, 10), 500))
        reloadSync()
    }

    // MARK: Appearance and defaults

    public func setSubtitleStyle(_ style: SubtitleStyle) {
        backend.setSubtitleStyle(style)
        reloadStyle()
    }
    /// Edits the style in place: `tracks.updateSubtitleStyle { $0.bold = true }` (starts from the engine's value).
    public func updateSubtitleStyle(_ change: (inout SubtitleStyle) -> Void) {
        let current = backend.subtitleStyle
        var style = current
        change(&style)
        if style != current { setSubtitleStyle(style) }
    }
    /// The global default tracks and languages (sidebar "Defaults"; VLC `audio-track`, `sub-language`…).
    public func setTrackDefaults(_ defaults: TrackDefaults) {
        backend.setTrackDefaults(defaults)
        reloadTrackDefaults()
    }
    public func updateTrackDefaults(_ change: (inout TrackDefaults) -> Void) {
        let current = backend.trackDefaults
        var defaults = current
        change(&defaults)
        if defaults != current { setTrackDefaults(defaults) }
    }

    // MARK: Subtitle timeline

    /// Loads cues of the selected subtitle track (empty when none or unsupported).
    public func loadSubtitleCues() {
        cuesTask?.cancel()
        cueGeneration += 1
        let generation = cueGeneration
        let mediaID = backend.currentMedia?.id
        guard let track = selectedTrack(of: .subtitle) else {
            subtitleCues = []
            return
        }
        let backend = self.backend
        cuesTask = Task { @MainActor [weak self] in
            let cues = await backend.subtitleCues(trackID: track.id)
            guard !Task.isCancelled, let self, self.cueGeneration == generation,
                  self.backend.currentMedia?.id == mediaID,
                  self.selectedTrack(of: .subtitle)?.id == track.id else { return }
            self.subtitleCues = cues
        }
    }

    // MARK: Events

    private func handle(_ event: PlayerEvent) {
        switch event {
        case .tracks(let kind):
            let previous = selectedTrack(of: .subtitle)?.id
            reloadTracks(kind)
            if kind == .subtitle, selectedTrack(of: .subtitle)?.id != previous, !subtitleCues.isEmpty || previous != nil {
                loadSubtitleCues()
            }
        case .media:
            cuesTask?.cancel()
            cuesTask = nil
            cueGeneration += 1
            subtitleCues = []
            for kind in TrackKind.allCases { reloadTracks(kind) }
        case .audioDevices: reloadDevices()
        case .synchronization: reloadSync()
        case .subtitleStyle: reloadStyle()
        case .trackDefaults: reloadTrackDefaults()
        default: break
        }
    }

    private func reloadTracks(_ kind: TrackKind) {
        let list = backend.tracks(of: kind)
        switch kind {
        case .video: videoTracks = list
        case .audio: audioTracks = list
        case .subtitle: subtitleTracks = list
        }
    }

    private func reloadDevices() {
        audioDevices = backend.audioDevices
        currentAudioDeviceID = backend.currentAudioDeviceID
    }

    private func reloadSync() {
        if backend.audioDelay != audioDelay { audioDelay = backend.audioDelay }
        if backend.subtitleDelay != subtitleDelay { subtitleDelay = backend.subtitleDelay }
        if backend.subtitleFPS != subtitleFPS { subtitleFPS = backend.subtitleFPS }
        if backend.subtitleDurationFactor != subtitleDurationFactor { subtitleDurationFactor = backend.subtitleDurationFactor }
        if backend.subtitleTextScale != subtitleTextScale { subtitleTextScale = backend.subtitleTextScale }
    }

    private func reloadStyle() {
        if backend.subtitleStyle != subtitleStyle { subtitleStyle = backend.subtitleStyle }
    }

    private func reloadTrackDefaults() {
        if backend.trackDefaults != trackDefaults { trackDefaults = backend.trackDefaults }
    }
}
