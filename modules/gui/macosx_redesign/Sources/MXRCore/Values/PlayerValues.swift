import Foundation

/// The player state, mirroring `enum vlc_player_state`.
public enum PlayerState: String, Sendable, Codable, Hashable {
    /// Nothing is playing (also the initial state).
    case stopped
    /// Media is opening or buffering before the first frame.
    case started
    case playing
    case paused
    /// Playback is being stopped.
    case stopping
}

/// What the current media allows (`VLC_PLAYER_CAP_*`).
public struct PlaybackCapabilities: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let seek = PlaybackCapabilities(rawValue: 1 << 0)
    public static let pause = PlaybackCapabilities(rawValue: 1 << 1)
    public static let changeRate = PlaybackCapabilities(rawValue: 1 << 2)
    /// Reverse playback (`VLC_PLAYER_CAP_REWIND`); see D014.
    public static let rewind = PlaybackCapabilities(rawValue: 1 << 3)
    /// `vlc_player_SetRecordingEnabled` is meaningful for this input.
    public static let record = PlaybackCapabilities(rawValue: 1 << 4)

    /// A typical local file.
    public static let file: PlaybackCapabilities = [.seek, .pause, .changeRate, .record]
}

/// Kind of elementary stream, mirroring `enum es_format_category_e` (VIDEO_ES, AUDIO_ES, SPU_ES).
public enum TrackKind: String, Sendable, Codable, Hashable, CaseIterable {
    case video
    case audio
    case subtitle
}

/// An elementary stream of the current media (`struct vlc_player_track`).
public struct Track: Identifiable, Hashable, Sendable {
    /// The VLC es id as a string (`vlc_es_id_GetStrId`, e.g. `"audio/1"`, `"spu/3"`). Stable while the media plays.
    public var id: String
    public var kind: TrackKind
    /// Display name as built by VLC ("Track 1 - [English]") or by the design ("English").
    public var name: String
    /// ISO 639 language code or name, if known.
    public var language: String?
    /// Codec description ("H.264", "AAC", "SubRip"), if known.
    public var codec: String?
    public var isSelected: Bool
    /// True for tracks loaded from a separate file (`vlc_player_AddAssociatedMedia`): "External Tracks".
    public var isExternal: Bool
    /// For external tracks, the file they came from.
    public var sourceURL: URL?
    /// For video tracks, the picture size in pixels.
    public var videoSize: CGSize?

    public init(id: String, kind: TrackKind, name: String, language: String? = nil, codec: String? = nil,
                isSelected: Bool = false, isExternal: Bool = false, sourceURL: URL? = nil, videoSize: CGSize? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.language = language
        self.codec = codec
        self.isSelected = isSelected
        self.isExternal = isExternal
        self.sourceURL = sourceURL
        self.videoSize = videoSize
    }
}

/// An audio output device (`aout_DevicesList`).
public struct AudioDevice: Identifiable, Hashable, Sendable, Codable {
    /// The aout device id ("" or "default" for the system default).
    public var id: String
    /// Name shown in the Output Device list ("Speakers", "Headphones", "MacBook Pro Speakers").
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A chapter of the current title (`struct vlc_player_chapter`). Shown in the Chapters tab (S24).
public struct Chapter: Identifiable, Hashable, Sendable {
    /// Index in the title's chapter list (0-based); also the id.
    public var index: Int
    public var name: String
    /// Start offset from the beginning of the title.
    public var time: MediaTime

    public var id: Int { index }

    public init(index: Int, name: String, time: MediaTime) {
        self.index = index
        self.name = name
        self.time = time
    }
}

/// A title of the current media (`struct vlc_player_title`): DVD titles, Matroska editions.
public struct MediaTitle: Identifiable, Hashable, Sendable {
    public var index: Int
    public var name: String
    public var length: MediaTime
    /// True for DVD/Blu-ray menus.
    public var isMenu: Bool
    public var chapters: [Chapter]

    public var id: Int { index }

    public init(index: Int, name: String, length: MediaTime, isMenu: Bool = false, chapters: [Chapter] = []) {
        self.index = index
        self.name = name
        self.length = length
        self.isMenu = isMenu
        self.chapters = chapters
    }
}

/// A program of a multi-program stream (DVB/TS service), `struct vlc_player_program`.
public struct MediaProgram: Identifiable, Hashable, Sendable {
    public var id: Int
    public var name: String
    public var isSelected: Bool
    public var isScrambled: Bool

    public init(id: Int, name: String, isSelected: Bool = false, isScrambled: Bool = false) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
        self.isScrambled = isScrambled
    }
}

/// A user bookmark on a media (media-library bookmark). Bookmarks tab (S23), created with ⌃B.
public struct Bookmark: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var mediaID: String
    /// Name shown in the list, e.g. "DON’T BLINK 1".
    public var name: String
    public var time: MediaTime

    public init(id: String, mediaID: String, name: String, time: MediaTime) {
        self.id = id
        self.mediaID = mediaID
        self.name = name
        self.time = time
    }
}

/// A-B repeat state (`vlc_player_GetAtoBLoop`).
public enum ABLoop: Hashable, Sendable {
    case off
    /// Point A is set, waiting for B.
    case pointA(MediaTime)
    /// Looping between A and B.
    case looping(a: MediaTime, b: MediaTime)
}

/// One subtitle line on the timeline (S21). Not provided by the engine; see D014.
public struct SubtitleCue: Hashable, Sendable {
    public var start: MediaTime
    public var end: MediaTime
    public var text: String

    public init(start: MediaTime, end: MediaTime, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// The "continue watching" question (`on_playback_restore_queried`, S12).
public struct RestorePrompt: Hashable, Sendable {
    public var mediaID: String
    /// Where playback would resume ("You’ve watched till 00:45:08 already.").
    public var time: MediaTime

    public init(mediaID: String, time: MediaTime) {
        self.mediaID = mediaID
        self.time = time
    }
}

/// Input statistics (`input_stats_t`), shown when "Show Statistics" is on.
public struct MediaStatistics: Hashable, Sendable {
    /// Input bitrate in kB/s.
    public var inputBitrate: Double
    /// Demux bitrate in kB/s.
    public var demuxBitrate: Double
    public var decodedVideoBlocks: Int
    public var displayedPictures: Int
    public var lostPictures: Int
    public var decodedAudioBlocks: Int
    public var playedAudioBuffers: Int
    public var lostAudioBuffers: Int

    public init(inputBitrate: Double = 0, demuxBitrate: Double = 0, decodedVideoBlocks: Int = 0, displayedPictures: Int = 0,
                lostPictures: Int = 0, decodedAudioBlocks: Int = 0, playedAudioBuffers: Int = 0, lostAudioBuffers: Int = 0) {
        self.inputBitrate = inputBitrate
        self.demuxBitrate = demuxBitrate
        self.decodedVideoBlocks = decodedVideoBlocks
        self.displayedPictures = displayedPictures
        self.lostPictures = lostPictures
        self.decodedAudioBlocks = decodedAudioBlocks
        self.playedAudioBuffers = playedAudioBuffers
        self.lostAudioBuffers = lostAudioBuffers
    }
}

/// How precisely to seek (`enum vlc_player_seek_speed`).
public enum SeekPrecision: Sendable, Hashable {
    /// Exact position; slower.
    case precise
    /// Nearest keyframe; used while dragging the seek bar.
    case fast
}

/// Sleep timer choices (sidebar Playback tab). Implemented app-side.
public enum SleepTimer: String, Sendable, Codable, Hashable, CaseIterable {
    case off
    case minutes15
    case minutes30
    case minutes45
    case minutes60
    case minutes90
    /// Pause when the current item ends.
    case endOfItem

    /// Label for the dropdown.
    public var title: String {
        switch self {
        case .off: "Off"
        case .minutes15: "15 minutes"
        case .minutes30: "30 minutes"
        case .minutes45: "45 minutes"
        case .minutes60: "1 hour"
        case .minutes90: "1 hour 30 minutes"
        case .endOfItem: "End of current item"
        }
    }

    /// The delay, or nil for `.off` and `.endOfItem`.
    public var interval: Duration? {
        switch self {
        case .off, .endOfItem: nil
        case .minutes15: .seconds(15 * 60)
        case .minutes30: .seconds(30 * 60)
        case .minutes45: .seconds(45 * 60)
        case .minutes60: .seconds(60 * 60)
        case .minutes90: .seconds(90 * 60)
        }
    }
}

/// Audio visualization for audio-only media (VLC `audio-visual` + `effect-list`).
/// Titles follow the Figma "Audio Visualizer" dropdown.
public enum AudioVisualization: String, Sendable, Codable, Hashable, CaseIterable {
    case disabled
    case spectrometer
    case scope
    case spectrum
    case waveform

    /// Label for the dropdown (Figma spells the second one "Spectometer").
    public var title: String {
        switch self {
        case .disabled: "Disabled"
        case .spectrometer: "Spectrometer"
        case .scope: "Scope"
        case .spectrum: "Spectrum"
        case .waveform: "Waveform"
        }
    }
}

/// Preferred default tracks, written to the VLC options `audio-track`, `audio-language`,
/// `sub-track`, `sub-language` (sidebar "Defaults" sections).
public struct TrackDefaults: Hashable, Sendable, Codable {
    /// 1-based preferred audio track number, nil = automatic.
    public var audioTrack: Int?
    /// Preferred audio language ("English", or an ISO code), nil = automatic.
    public var audioLanguage: String?
    /// 1-based preferred subtitle track number, nil = automatic.
    public var subtitleTrack: Int?
    public var subtitleLanguage: String?

    public init(audioTrack: Int? = nil, audioLanguage: String? = nil, subtitleTrack: Int? = nil, subtitleLanguage: String? = nil) {
        self.audioTrack = audioTrack
        self.audioLanguage = audioLanguage
        self.subtitleTrack = subtitleTrack
        self.subtitleLanguage = subtitleLanguage
    }
}

extension TrackDefaults {
    /// True when no preference is set.
    public var isEmpty: Bool { audioTrack == nil && audioLanguage == nil && subtitleTrack == nil && subtitleLanguage == nil }

    /// Whether two designations name the same language: "English", "en", "eng" and "EN" all match.
    public static func language(_ lhs: String, matches rhs: String) -> Bool {
        let left = normalizedLanguage(lhs)
        return !left.isEmpty && left == normalizedLanguage(rhs)
    }

    /// The English name of a language code ("jpn" → "japanese"), or the lower-cased text.
    static func normalizedLanguage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard (2...3).contains(trimmed.count), let name = Locale(identifier: "en_US_POSIX").localizedString(forLanguageCode: trimmed) else {
            return trimmed
        }
        return name.lowercased()
    }
}

/// Settings for one media that the engine must have when its input opens. VLC reads the track
/// preferences (`audio-track`, `audio-language`, `sub-track`, `sub-language`) only at input start,
/// so per-show presets travel as per-input options (`:audio-language=jpn`) instead of being set later.
public struct MediaStartOptions: Hashable, Sendable {
    /// Track preferences for this media only; nil fields fall back to the global ``TrackDefaults``.
    public var trackPreferences: TrackDefaults

    public init(trackPreferences: TrackDefaults = TrackDefaults()) {
        self.trackPreferences = trackPreferences
    }

    /// True when there is nothing to pass.
    public var isEmpty: Bool { trackPreferences.isEmpty }
}

/// Teletext of the current media (`vlc_player_*Teletext*`).
public struct TeletextState: Hashable, Sendable {
    /// True when the media has a teletext track (`vlc_player_HasTeletextMenu`).
    public var isAvailable: Bool
    public var isEnabled: Bool
    /// Current page, 100...899 (0 when unknown).
    public var page: Int
    /// Transparent background over the video.
    public var isTransparent: Bool

    public init(isAvailable: Bool = false, isEnabled: Bool = false, page: Int = 0, isTransparent: Bool = false) {
        self.isAvailable = isAvailable
        self.isEnabled = isEnabled
        self.page = page
        self.isTransparent = isTransparent
    }

    /// No teletext.
    public static let unavailable = TeletextState()
}
