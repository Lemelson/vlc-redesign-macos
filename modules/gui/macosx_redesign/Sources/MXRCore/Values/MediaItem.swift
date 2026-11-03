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
    /// True for a file added with Add File (not found by a folder scan): "Remove from Library"
    /// takes it out again. Optional so pins and recents saved before it still decode.
    public var importedFile: Bool? = nil
    public var isImported: Bool { importedFile == true }

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

    /// Items saved in pins and recents by another version still decode: only the id, MRL and title
    /// are required; a missing play count or favorite flag reads as the default, and a kind this
    /// version does not know is guessed from the MRL.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mrl = try c.decode(String.self, forKey: .mrl)
        let kind = (try? c.decodeIfPresent(MediaKind.self, forKey: .kind))
            ?? URL(string: mrl).map(Self.kind(of:)) ?? .unknown
        self.init(id: try c.decode(String.self, forKey: .id), mrl: mrl, title: try c.decode(String.self, forKey: .title),
                  fileName: try c.decodeIfPresent(String.self, forKey: .fileName), kind: kind,
                  duration: try c.decodeIfPresent(MediaTime.self, forKey: .duration),
                  progress: try c.decodeIfPresent(Double.self, forKey: .progress),
                  playCount: try c.decodeIfPresent(Int.self, forKey: .playCount) ?? 0,
                  isFavorite: try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false,
                  lastPlayedDate: try c.decodeIfPresent(Date.self, forKey: .lastPlayedDate),
                  addedDate: try c.decodeIfPresent(Date.self, forKey: .addedDate),
                  artist: try c.decodeIfPresent(String.self, forKey: .artist),
                  album: try c.decodeIfPresent(String.self, forKey: .album),
                  albumArtist: try c.decodeIfPresent(String.self, forKey: .albumArtist),
                  genre: try c.decodeIfPresent(String.self, forKey: .genre),
                  trackNumber: try c.decodeIfPresent(Int.self, forKey: .trackNumber),
                  discNumber: try c.decodeIfPresent(Int.self, forKey: .discNumber),
                  year: try c.decodeIfPresent(Int.self, forKey: .year),
                  episode: try c.decodeIfPresent(EpisodeInfo.self, forKey: .episode),
                  folder: try c.decodeIfPresent(FolderReference.self, forKey: .folder),
                  artworkURL: try c.decodeIfPresent(URL.self, forKey: .artworkURL),
                  videoSize: try c.decodeIfPresent(CGSize.self, forKey: .videoSize))
        playlistOccurrence = try c.decodeIfPresent(PlaylistOccurrence.self, forKey: .playlistOccurrence)
        importedFile = try c.decodeIfPresent(Bool.self, forKey: .importedFile)
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
        if audioExtensions.contains(ext) || (audioFileExtensions.contains(ext) && !videoFileExtensions.contains(ext))
            || UTType(filenameExtension: ext)?.conforms(to: .audio) == true { return .audio }
        return .video
    }

    /// True for a file Add File puts in the library: a video or audio type of VLC's lists. Text,
    /// images, subtitles and playlists are not media of their own (they never list under Videos).
    public static func isLibraryMedia(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let ext = url.pathExtension.lowercased()
        return videoFileExtensions.contains(ext) || audioFileExtensions.contains(ext)
    }

    /// VLC's `EXTENSIONS_VIDEO` (include/vlc_interface.h).
    public static let videoFileExtensions: Set<String> = [
        "3g2", "3gp", "3gp2", "3gpp", "amrec", "amv", "asf", "avi", "bik", "bin", "crf", "dav", "divx", "drc", "dv",
        "dvr-ms", "evo", "f4v", "flv", "gvi", "gxf", "iso", "k3g", "m1v", "m2v", "m2t", "m2ts", "m4v", "mkv", "mov",
        "mp2", "mp2v", "mp4", "mp4v", "mpe", "mpeg", "mpeg1", "mpeg2", "mpeg4", "mpg", "mpv2", "mts", "mtv", "mxf",
        "mxg", "nsv", "nuv", "ogg", "ogm", "ogv", "ogx", "ps", "qt", "rec", "rm", "rmvb", "rpl", "skm", "thp", "tod",
        "tp", "ts", "tts", "txd", "vob", "vp6", "vro", "webm", "wm", "wmv", "wtv", "xesc",
    ]

    /// VLC's `EXTENSIONS_AUDIO` (include/vlc_interface.h).
    public static let audioFileExtensions: Set<String> = [
        "3ga", "669", "a52", "aac", "ac3", "adt", "adts", "aif", "aifc", "aiff", "alac", "amb", "amr", "aob", "ape",
        "au", "awb", "caf", "dts", "dsf", "dff", "flac", "it", "kar", "m4a", "m4b", "m4p", "m5p", "mid", "mka", "mlp", "mod",
        "mpa", "mp1", "mp2", "mp3", "mpc", "mpga", "mus", "oga", "ogg", "oma", "opus", "qcp", "ra", "rmi", "s3m", "sid",
        "spx", "tak", "thd", "tta", "voc", "vqf", "w64", "wav", "wma", "wv", "xa", "xm",
    ]

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
    /// containing folder id, otherwise the item itself (a file opened directly; live run 2: a new
    /// preset for it was never selected because it had nowhere to be remembered).
    public var presetKey: String? {
        if let episode { return "show:" + episode.showName.lowercased() }
        if let folder { return "folder:" + folder.id }
        return "media:" + id
    }

    /// The resume position derived from `progress` and `duration`, if any.
    public var resumeTime: MediaTime? {
        guard isInProgress, let progress, let duration else { return nil }
        return duration * progress
    }
}
