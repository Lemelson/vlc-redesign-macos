import Foundation
import UniformTypeIdentifiers

/// What kind of media an item is. Drives the player look (video vs music now-playing, S34) and icons.
public enum MediaKind: String, Sendable, Codable, Hashable, CaseIterable {
    case video
    case audio
    /// A network stream (radio, TV channel, live URL). Usually not seekable.
    case stream
    /// A disc (DVD, Blu-ray, audio CD).
    case disc
    case unknown
}

/// Episode information parsed by the media library (VLC `vlc_ml_show_episode_t`).
public struct EpisodeInfo: Hashable, Sendable, Codable {
    /// Media-library id of the show (`ml:show:<id>`), if known.
    public var showID: String?
    /// The show name, e.g. "The Wand".
    public var showName: String
    public var season: Int
    public var episode: Int

    public init(showID: String? = nil, showName: String, season: Int, episode: Int) {
        self.showID = showID
        self.showName = showName
        self.season = season
        self.episode = episode
    }

    /// "S01E04".
    public var code: String {
        "S" + String(format: "%02d", season) + "E" + String(format: "%02d", episode)
    }
}

/// A reference to the folder that contains a media item (top-bar folder chip "S01", S28).
public struct FolderReference: Hashable, Sendable, Codable {
    /// Library folder id (`LibraryLocation.folder(id)`).
    public var id: String
    /// Display name, e.g. "S01".
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One playable thing: a file, a stream, a disc or a library media.
///
/// Ids: media-library items use `"ml:<numeric id>"`; anything else uses its MRL. Ids are stable
/// across launches for library items, so they can be persisted (pins, presets, recents).
public struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var playlistOccurrence: PlaylistOccurrence? = nil
    /// The VLC MRL (`file:///…`, `https://…`, `dvd://…`).
    public var mrl: String
    /// Title from metadata, or the file name when there is none (VLC behavior).
    public var title: String
    /// The file name including extension ("The_Wand_S01E05.mp4"); nil for streams without a path.
    public var fileName: String?
    public var kind: MediaKind
    /// Length, or nil when unknown or live.
    public var duration: MediaTime?

    // Library state (vlc_ml_media_t)
    /// Last playback position as a fraction 0...1 (`f_progress`); nil when never started.
    public var progress: Double?
    /// Number of completed plays (`i_playcount`). Greater than zero means watched.
    public var playCount: Int
    public var isFavorite: Bool
    public var lastPlayedDate: Date?
    public var addedDate: Date?

    // Metadata
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: Int?
    public var episode: EpisodeInfo?
    /// Containing library folder, when the item is in the library.
    public var folder: FolderReference?
    /// Cover art or thumbnail file, when the library has one. Prefer `ThumbnailBackend` for images.
    public var artworkURL: URL?
    /// Video resolution in pixels, when known.
    public var videoSize: CGSize?

    public init(
        id: String,
        mrl: String,
        title: String,
        fileName: String? = nil,
        kind: MediaKind,
        duration: MediaTime? = nil,
        progress: Double? = nil,
        playCount: Int = 0,
        isFavorite: Bool = false,
        lastPlayedDate: Date? = nil,
        addedDate: Date? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        genre: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        year: Int? = nil,
        episode: EpisodeInfo? = nil,
        folder: FolderReference? = nil,
        artworkURL: URL? = nil,
        videoSize: CGSize? = nil
    ) {
        self.id = id
        self.mrl = mrl
        self.title = title
        self.fileName = fileName
        self.kind = kind
        self.duration = duration
        self.progress = progress
        self.playCount = playCount
        self.isFavorite = isFavorite
        self.lastPlayedDate = lastPlayedDate
        self.addedDate = addedDate
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.episode = episode
        self.folder = folder
        self.artworkURL = artworkURL
        self.videoSize = videoSize
    }

    /// Creates an item for a local file or a URL that is not (yet) in the library.
    public init(url: URL) {
        let kind = Self.kind(of: url)
        let name = url.isFileURL ? url.lastPathComponent : (url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent)
        self.init(id: url.absoluteString, mrl: url.absoluteString, title: name,
                  fileName: url.isFileURL ? url.lastPathComponent : nil, kind: kind)
    }

    /// What a URL that VLC has not parsed yet most likely holds: a network URL is a stream; a file is
    /// audio when its type says so (UTType, plus containers macOS does not know), video otherwise.
    public static func kind(of url: URL) -> MediaKind {
        guard url.isFileURL else { return .stream }
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .audio) == true { return .audio }
        return .video
    }

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "oga", "opus", "wma", "alac", "ape", "mka",
    ]

    // MARK: Derived

    /// True once the item was played to the end at least once (dimmed rows, full progress bar).
    public var isWatched: Bool { playCount > 0 }

    /// True when the item was started but not finished (Continue Watching, resume marker).
    public var isInProgress: Bool {
        guard let progress else { return false }
        return progress > 0 && progress < 1 && !isWatched
    }

    /// The fraction to draw as the orange progress line under thumbnails: 1 when watched.
    public var displayProgress: Double? {
        if isWatched { return 1 }
        guard let progress, progress > 0 else { return nil }
        return min(progress, 1)
    }

    /// Title for the top bar: "The Wand S01E04" for episodes, "untangle" for songs, else the title.
    public var displayTitle: String {
        if let episode { return "\(episode.showName) \(episode.code)" }
        return title
    }

    /// Text for library and queue rows: "untangle - juxtopposed" for songs with an artist,
    /// otherwise the file name ("The_Wand_S01E05.mp4"), otherwise the title.
    public var listTitle: String {
        if kind == .audio, let artist, !artist.isEmpty { return "\(title) - \(artist)" }
        return fileName ?? title
    }

    /// Key used to remember per-show presets (spec 07): the show name for episodes, otherwise the
    /// containing folder id. Nil when the item belongs to neither.
    public var presetKey: String? {
        if let episode { return "show:" + episode.showName.lowercased() }
        if let folder { return "folder:" + folder.id }
        return nil
    }

    /// The resume position derived from `progress` and `duration`, if any.
    public var resumeTime: MediaTime? {
        guard isInProgress, let progress, let duration else { return nil }
        return duration * progress
    }
}
