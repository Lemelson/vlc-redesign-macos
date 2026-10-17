import Foundation
import Observation

/// Which parts of the playback state a preset captures.
public struct PresetSections: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Subtitle delay, speed, duration factor, text scale, style and preferred subtitle track/language.
    public static let subtitles = PresetSections(rawValue: 1 << 0)
    /// Audio delay, preferred audio track/language and audio effects.
    public static let audio = PresetSections(rawValue: 1 << 1)
    /// Video effects.
    public static let video = PresetSections(rawValue: 1 << 2)

    public static let all: PresetSections = [.subtitles, .audio, .video]
}

/// A named set of playback settings ("Anime", "Loud and then Quiet Movies", "The Wand Subtitle Preset").
/// Nil effect fields are left untouched; captured track sections explicitly retain Automatic.
public struct PlaybackPreset: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    /// Presence records a captured section; nil track/language inside means Automatic.
    public struct TrackSelection: Hashable, Sendable, Codable {
        public var track: Int?
        public var language: String?
        public init(track: Int?, language: String?) { self.track = track; self.language = language }
    }
    public var subtitleTrackDefaults: TrackSelection?
    public var audioTrackDefaults: TrackSelection?
    public var subtitleDelay: MediaTime?
    public var subtitleFPS: Double?
    public var subtitleDurationFactor: Double?
    public var subtitleTextScale: Int?
    public var subtitleStyle: SubtitleStyle?
    public var subtitleTrack: Int?
    public var subtitleLanguage: String?
    public var audioDelay: MediaTime?
    public var audioTrack: Int?
    public var audioLanguage: String?
    public var audioEffects: AudioEffects?
    public var videoEffects: VideoEffects?

    public init(id: String = UUID().uuidString, name: String, subtitleDelay: MediaTime? = nil, subtitleFPS: Double? = nil,
                subtitleDurationFactor: Double? = nil, subtitleTextScale: Int? = nil, subtitleStyle: SubtitleStyle? = nil,
                subtitleTrack: Int? = nil, subtitleLanguage: String? = nil, audioDelay: MediaTime? = nil, audioTrack: Int? = nil,
                audioLanguage: String? = nil, audioEffects: AudioEffects? = nil, videoEffects: VideoEffects? = nil) {
        self.id = id
        self.name = name
        self.subtitleDelay = subtitleDelay
        self.subtitleFPS = subtitleFPS
        self.subtitleDurationFactor = subtitleDurationFactor
        self.subtitleTextScale = subtitleTextScale
        self.subtitleStyle = subtitleStyle
        self.subtitleTrack = subtitleTrack
        self.subtitleLanguage = subtitleLanguage
        self.audioDelay = audioDelay
        self.audioTrack = audioTrack
        self.audioLanguage = audioLanguage
        self.audioEffects = audioEffects
        self.videoEffects = videoEffects
    }

    /// Id of the built-in "Default Preset" (VLC defaults; cannot be deleted or renamed).
    public static let defaultID = "default"

    /// "Default Preset": every value at VLC's default.
    public static let `default` = PlaybackPreset(
        id: defaultID, name: "Default Preset", subtitleDelay: .zero, subtitleFPS: 0, subtitleDurationFactor: 0,
        subtitleTextScale: 100, subtitleStyle: .default, subtitleTrack: nil, subtitleLanguage: nil, audioDelay: .zero,
        audioTrack: nil, audioLanguage: nil, audioEffects: .default, videoEffects: .default)
}

/// Per-show presets (spec 07 "Remember things for me"): named presets, and which preset each show
/// (``MediaItem/presetKey``) uses. Persisted to `presets.json`.
@MainActor
@Observable
public final class PresetStore {
    /// "Default Preset" first, then user presets in creation order.
    public private(set) var presets: [PlaybackPreset] = [.default]
    /// presetKey (show/folder) → preset id.
    public private(set) var assignments: [String: String] = [:]

    @ObservationIgnored private let file: JSONFileStore<Snapshot>

    private struct Snapshot: Codable {
        var presets: [PlaybackPreset]
        var assignments: [String: String]
    }

    /// Loads presets from `location` (in memory: starts with only the default preset).
    public init(location: PersistenceLocation) {
        file = JSONFileStore(location: location, fileName: "presets.json")
        if let snapshot = file.load() {
            presets = [.default] + snapshot.presets.filter { $0.id != PlaybackPreset.defaultID }
            assignments = snapshot.assignments
        }
    }

    /// User presets (without the default).
    public var customPresets: [PlaybackPreset] { presets.filter { $0.id != PlaybackPreset.defaultID } }

    public func preset(id: String) -> PlaybackPreset? { presets.first { $0.id == id } }

    /// The preset assigned to the media's show or folder, if any.
    public func preset(for media: MediaItem) -> PlaybackPreset? {
        guard let key = media.presetKey, let id = assignments[key] else { return nil }
        return preset(id: id)
    }

    /// Adds a preset (or replaces one with the same id) and saves.
    @discardableResult
    public func save(_ preset: PlaybackPreset) -> PlaybackPreset {
        guard preset.id != PlaybackPreset.defaultID else { return preset }
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        persist()
        return preset
    }

    public func rename(id: String, to name: String) {
        guard id != PlaybackPreset.defaultID, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = name
        persist()
    }

    /// Deletes a preset and its assignments.
    public func delete(id: String) {
        guard id != PlaybackPreset.defaultID else { return }
        presets.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
        persist()
    }

    /// Makes `presetID` the preset of the media's show/folder (nil removes the assignment).
    public func assign(_ presetID: String?, to media: MediaItem) {
        guard let key = media.presetKey else { return }
        assignments[key] = presetID
        persist()
    }

    /// Captures the current state into a new preset (sidebar "New Preset").
    @discardableResult
    public func capture(name: String, sections: PresetSections = .all, tracks: TracksModel,
                        audio: AudioEffectsModel, video: VideoEffectsModel) -> PlaybackPreset {
        var preset = PlaybackPreset(name: name)
        if sections.contains(.subtitles) {
            preset.subtitleTrackDefaults = .init(track: tracks.trackDefaults.subtitleTrack, language: tracks.trackDefaults.subtitleLanguage)
            preset.subtitleDelay = tracks.subtitleDelay
            preset.subtitleFPS = tracks.subtitleFPS
            preset.subtitleDurationFactor = tracks.subtitleDurationFactor
            preset.subtitleTextScale = tracks.subtitleTextScale
            preset.subtitleStyle = tracks.subtitleStyle
            preset.subtitleTrack = tracks.trackDefaults.subtitleTrack
            preset.subtitleLanguage = tracks.trackDefaults.subtitleLanguage
        }
        if sections.contains(.audio) {
            preset.audioTrackDefaults = .init(track: tracks.trackDefaults.audioTrack, language: tracks.trackDefaults.audioLanguage)
            preset.audioDelay = tracks.audioDelay
            preset.audioTrack = tracks.trackDefaults.audioTrack
            preset.audioLanguage = tracks.trackDefaults.audioLanguage
            preset.audioEffects = audio.effects
        }
        if sections.contains(.video) {
            preset.videoEffects = video.effects
        }
        return save(preset)
    }

    /// Applies included sections, including captured Automatic track choices, to the player.
    public func apply(_ preset: PlaybackPreset, tracks: TracksModel, audio: AudioEffectsModel, video: VideoEffectsModel) {
        if let value = preset.subtitleDelay { tracks.setSubtitleDelay(value) }
        if let value = preset.subtitleFPS { tracks.setSubtitleFPS(value) }
        if let value = preset.subtitleDurationFactor { tracks.setSubtitleDurationFactor(value) }
        if let value = preset.subtitleTextScale { tracks.setSubtitleTextScale(value) }
        if let value = preset.subtitleStyle { tracks.setSubtitleStyle(value) }
        if let value = preset.audioDelay { tracks.setAudioDelay(value) }
        // Legacy capture wrote every effect field for each included section. Recover those
        // sections, while retaining patch semantics for older manually constructed sparse presets.
        let subtitleDefaults = preset.subtitleTrackDefaults ?? (
            preset.subtitleDelay != nil && preset.subtitleFPS != nil && preset.subtitleDurationFactor != nil
                && preset.subtitleTextScale != nil && preset.subtitleStyle != nil
            ? .init(track: preset.subtitleTrack, language: preset.subtitleLanguage) : nil)
        let audioDefaults = preset.audioTrackDefaults ?? (
            preset.audioDelay != nil && preset.audioEffects != nil
            ? .init(track: preset.audioTrack, language: preset.audioLanguage) : nil)
        tracks.updateTrackDefaults { defaults in
            if preset.id == PlaybackPreset.defaultID {
                defaults = TrackDefaults()
                return
            }
            if let subtitleDefaults {
                defaults.subtitleTrack = subtitleDefaults.track
                defaults.subtitleLanguage = subtitleDefaults.language
            } else {
                if let value = preset.subtitleTrack { defaults.subtitleTrack = value }
                if let value = preset.subtitleLanguage { defaults.subtitleLanguage = value }
            }
            if let audioDefaults {
                defaults.audioTrack = audioDefaults.track
                defaults.audioLanguage = audioDefaults.language
            } else {
                if let value = preset.audioTrack { defaults.audioTrack = value }
                if let value = preset.audioLanguage { defaults.audioLanguage = value }
            }
        }
        if let value = preset.audioEffects { audio.set(value) }
        if let value = preset.videoEffects { video.set(value) }
    }

    private func persist() {
        file.save(Snapshot(presets: customPresets, assignments: assignments))
    }
}
