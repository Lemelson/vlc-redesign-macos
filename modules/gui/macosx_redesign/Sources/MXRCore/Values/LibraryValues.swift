import Foundation
import CryptoKit

/// The library categories of the icon rail and the full-window sidebar (S42, S43), in design order.
public enum LibraryCategory: String, Sendable, Codable, Hashable, CaseIterable {
    case home, videos, music, network, playlists, recent

    /// Label as in the design.
    public var title: String {
        switch self {
        case .home: "Home"
        case .videos: "Videos"
        case .music: "Music"
        case .network: "Network"
        case .playlists: "Playlists"
        case .recent: "Recent"
        }
    }

    /// The root location of the category.
    public var location: LibraryLocation {
        switch self {
        case .home: .home
        case .videos: .videos
        case .music: .music
        case .network: .network
        case .playlists: .playlists
        case .recent: .recent
        }
    }
}

/// A place in the library that can be shown, navigated to (back/forward, breadcrumb) and pinned.
public enum LibraryLocation: Hashable, Sendable, Codable {
    case home
    case homeSection(LibraryHomeSectionKind)
    /// Video entry points ("Shows", "Films", "Anime").
    case videos
    /// Music root: links to Songs, Albums, Artists, Genres.
    case music
    /// Audio folders ("Songs" ▸ "My Songs").
    case songs
    case albums
    case artists
    case genres
    case network
    case playlists
    case recent
    /// A folder (entry point or subfolder) by library id.
    case folder(String)
    case album(String)
    case artist(String)
    case genre(String)
    case playlist(String)
    case show(String)
    /// A saved network stream that expands to several items (an m3u, "TV Channels").
    case stream(String)

    /// The rail category this location belongs to (which rail icon is active).
    public var category: LibraryCategory {
        switch self {
        case .home, .homeSection: .home
        case .videos, .show: .videos
        case .music, .songs, .albums, .artists, .genres, .album, .artist, .genre: .music
        case .network, .stream: .network
        case .playlists, .playlist: .playlists
        case .recent: .recent
        case .folder: .videos
        }
    }
}

/// A folder in the library (`vlc_ml_folder_t`).
public struct LibraryFolder: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var url: URL?
    /// Number of direct children (subfolders + media), if known.
    public var itemCount: Int?
    /// Main content type, for the icon.
    public var contentKind: MediaKind
    /// True for an indexed root folder (entry point).
    public var isEntryPoint: Bool

    public init(id: String, name: String, url: URL? = nil, itemCount: Int? = nil, contentKind: MediaKind = .video, isEntryPoint: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.itemCount = itemCount
        self.contentKind = contentKind
        self.isEntryPoint = isEntryPoint
    }
}

/// A saved playlist (`vlc_ml_playlist_t`).
public struct Playlist: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var itemCount: Int
    public var duration: MediaTime?
    /// Custom thumbnail chosen in the New Playlist dialog, if any.
    public var artworkURL: URL?
    public var isFavorite: Bool

    public init(id: String, name: String, itemCount: Int = 0, duration: MediaTime? = nil, artworkURL: URL? = nil, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
        self.duration = duration
        self.artworkURL = artworkURL
        self.isFavorite = isFavorite
    }
}

/// An album (`vlc_ml_album_t`).
public struct Album: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var artist: String?
    public var year: Int?
    public var trackCount: Int
    public var duration: MediaTime?
    public var artworkURL: URL?

    public init(id: String, title: String, artist: String? = nil, year: Int? = nil, trackCount: Int = 0, duration: MediaTime? = nil, artworkURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.year = year
        self.trackCount = trackCount
        self.duration = duration
        self.artworkURL = artworkURL
    }
}

/// An artist (`vlc_ml_artist_t`).
public struct Artist: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var albumCount: Int
    public var trackCount: Int
    public var artworkURL: URL?

    public init(id: String, name: String, albumCount: Int = 0, trackCount: Int = 0, artworkURL: URL? = nil) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.trackCount = trackCount
        self.artworkURL = artworkURL
    }
}

/// A genre (`vlc_ml_genre_t`).
public struct Genre: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var trackCount: Int

    public init(id: String, name: String, trackCount: Int = 0) {
        self.id = id
        self.name = name
        self.trackCount = trackCount
    }
}

/// A TV show (`vlc_ml_show_t`).
public struct Show: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var seasonCount: Int
    public var episodeCount: Int
    public var artworkURL: URL?

    public init(id: String, name: String, seasonCount: Int = 0, episodeCount: Int = 0, artworkURL: URL? = nil) {
        self.id = id
        self.name = name
        self.seasonCount = seasonCount
        self.episodeCount = episodeCount
        self.artworkURL = artworkURL
    }
}

/// A saved network stream of the Network category ("Podcasts", "Radio", "TV Channels").
/// Several URLs, or one m3u, make it a stream playlist.
public struct NetworkStream: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var urls: [URL]
    /// Number of entries once expanded (an m3u of channels), if known.
    public var itemCount: Int?

    public init(id: String, name: String, urls: [URL], itemCount: Int? = nil) {
        self.id = id
        self.name = name
        self.urls = urls
        self.itemCount = itemCount
    }
}

/// A navigation row inside a category root (Music ▸ Songs / Albums / Artists / Genres).
public struct LibraryLink: Hashable, Sendable, Codable {
    /// Stable identity when several links share a title. Nil keeps the original title identity.
    public var id: String?
    public var title: String
    public var destination: LibraryLocation
    /// Icon name from `redesign/design/figma/ICONS.md` (resolved by MXRDesign).
    public var iconName: String

    public init(id: String? = nil, title: String, destination: LibraryLocation, iconName: String) {
        self.id = id
        self.title = title
        self.destination = destination
        self.iconName = iconName
    }
}

/// One row or tile of a library page.
public enum LibraryEntry: Identifiable, Hashable, Sendable {
    case media(MediaItem)
    case folder(LibraryFolder)
    case playlist(Playlist)
    case album(Album)
    case artist(Artist)
    case genre(Genre)
    case show(Show)
    case stream(NetworkStream)
    case link(LibraryLink)

    /// Unique across kinds (prefixed).
    public var id: String {
        switch self {
        case .media(let m): m.playlistOccurrence.map { "occurrence:\($0.playlistID):\($0.revision):\($0.position)" } ?? ("media:" + m.id)
        case .folder(let f): "folder:" + f.id
        case .playlist(let p): "playlist:" + p.id
        case .album(let a): "album:" + a.id
        case .artist(let a): "artist:" + a.id
        case .genre(let g): "genre:" + g.id
        case .show(let s): "show:" + s.id
        case .stream(let s): "stream:" + s.id
        case .link(let l): "link:" + (l.id ?? l.title)
        }
    }

    /// Row text: media use ``MediaItem/listTitle``.
    public var title: String {
        switch self {
        case .media(let m): m.listTitle
        case .folder(let f): f.name
        case .playlist(let p): p.name
        case .album(let a): a.title
        case .artist(let a): a.name
        case .genre(let g): g.name
        case .show(let s): s.name
        case .stream(let s): s.name
        case .link(let l): l.title
        }
    }

    /// Where clicking the entry navigates; nil for media (clicking plays them).
    public var destination: LibraryLocation? {
        switch self {
        case .media: nil
        case .folder(let f): .folder(f.id)
        case .playlist(let p): .playlist(p.id)
        case .album(let a): .album(a.id)
        case .artist(let a): .artist(a.id)
        case .genre(let g): .genre(g.id)
        case .show(let s): .show(s.id)
        case .stream(let s): (s.itemCount ?? s.urls.count) > 1 ? .stream(s.id) : nil
        case .link(let l): l.destination
        }
    }

    /// The media, for `.media` entries.
    public var media: MediaItem? {
        if case .media(let m) = self { return m }
        return nil
    }
}

/// Library sort orders, exactly the Figma "Sorting Options" list (S32).
public enum LibrarySort: String, Sendable, Codable, Hashable, CaseIterable {
    case unwatchedFirst, watchedFirst, newestFirst, oldestFirst, titleAscending, titleDescending
    case artistAscending, artistDescending, albumAscending, albumDescending
    case trackNumberAscending, trackNumberDescending, uriAscending, uriDescending
    case discNumberAscending, discNumberDescending

    public var title: String {
        switch self {
        case .unwatchedFirst: "Unwatched First"
        case .watchedFirst: "Watched First"
        case .newestFirst: "Newest First"
        case .oldestFirst: "Oldest First"
        case .titleAscending: "Title A-Z"
        case .titleDescending: "Title Z-A"
        case .artistAscending: "Artist A-Z"
        case .artistDescending: "Artist Z-A"
        case .albumAscending: "Album A-Z"
        case .albumDescending: "Album Z-A"
        case .trackNumberAscending: "Track Number Ascending"
        case .trackNumberDescending: "Track Number Descending"
        case .uriAscending: "URI Ascending"
        case .uriDescending: "URI Descending"
        case .discNumberAscending: "Disc Number Ascending"
        case .discNumberDescending: "Disc Number Descending"
        }
    }

    /// Sorts that make sense for video lists (the first six of the Figma menu).
    public static let videoSorts: [LibrarySort] = [.unwatchedFirst, .watchedFirst, .newestFirst, .oldestFirst, .titleAscending, .titleDescending]

    /// The sorts offered at `location`.
    public static func available(at location: LibraryLocation, category: LibraryCategory? = nil) -> [LibrarySort] {
        if case .homeSection = location { return [] }
        return switch category ?? location.category {
        case .music: allCases.filter { $0 != .unwatchedFirst && $0 != .watchedFirst }
        default: videoSorts
        }
    }
}

/// Grid or list (Figma "View Options").
public enum LibraryViewMode: String, Sendable, Codable, Hashable, CaseIterable {
    case grid
    case list

    public var title: String { self == .grid ? "Grid View" : "List View" }
}

/// Parameters of a paged library query (`vlc_ml_query_params_t`).
public struct LibraryQuery: Hashable, Sendable {
    public var sort: LibrarySort
    /// Search pattern; empty = no filter.
    public var searchText: String
    public var offset: Int
    public var limit: Int

    public init(sort: LibrarySort = .titleAscending, searchText: String = "", offset: Int = 0, limit: Int = 100) {
        self.sort = sort
        self.searchText = searchText
        self.offset = offset
        self.limit = limit
    }
}

/// The "+" row a page offers at its top ("Add", "Add Network Stream", "Create playlist").
public enum LibraryAddAction: String, Sendable, Codable, Hashable {
    /// Add files or a folder to the library (folder roots).
    case add
    case addNetworkStream
    case createPlaylist

    public var title: String {
        switch self {
        case .add: "Add"
        case .addNetworkStream: "Add Network Stream"
        case .createPlaylist: "Create playlist"
        }
    }
}

/// One page of results.
public struct LibraryPage: Hashable, Sendable {
    public var location: LibraryLocation
    public var entries: [LibraryEntry]
    /// Total number of entries at the location (for "15 items" and paging).
    public var totalCount: Int
    /// Offset of `entries[0]` in the full result.
    public var offset: Int
    /// The "+" row to show above the entries, if any.
    public var addAction: LibraryAddAction?

    public init(location: LibraryLocation, entries: [LibraryEntry], totalCount: Int, offset: Int = 0, addAction: LibraryAddAction? = nil) {
        self.location = location
        self.entries = entries
        self.totalCount = totalCount
        self.offset = offset
        self.addAction = addAction
    }
}

/// Sections of the Home page (S40, S43), in design order.
public enum LibraryHomeSectionKind: String, Sendable, Codable, Hashable, CaseIterable {
    case continueWatching, listenAgain, frequentFolders, frequentPlaylists, frequentArtists, latestStreams

    public var title: String {
        switch self {
        case .continueWatching: "Continue Watching"
        case .listenAgain: "Listen Again"
        case .frequentFolders: "Frequently Visited Folders"
        case .frequentPlaylists: "Frequently Visited Playlists"
        case .frequentArtists: "Frequently Listened Artists"
        case .latestStreams: "Latest Streams"
        }
    }

    /// How many entries Home shows in this section's row (S43: up to 20 recent media, up to 8
    /// folders, playlists, artists or streams). The section's "›" page lists all of them.
    /// Backends cap Home to this so a large history is never bridged just to draw a row.
    public var homeLimit: Int {
        switch self {
        case .continueWatching, .listenAgain: 20
        case .frequentFolders, .frequentPlaylists, .frequentArtists, .latestStreams: 8
        }
    }
}

/// A Home section with its entries. Empty sections are not returned.
public struct LibraryHomeSection: Identifiable, Hashable, Sendable {
    public var kind: LibraryHomeSectionKind
    public var entries: [LibraryEntry]
    /// Where the "›" after the title navigates.
    public var destination: LibraryLocation?

    public var id: LibraryHomeSectionKind { kind }
    public var title: String { kind.title }

    public init(kind: LibraryHomeSectionKind, entries: [LibraryEntry], destination: LibraryLocation? = nil) {
        self.kind = kind
        self.entries = entries
        self.destination = destination
    }
}

/// One breadcrumb element ("Videos ▸ Shows ▸ The Wand ▸ S01").
public struct LibraryCrumb: Hashable, Sendable {
    public var title: String
    public var location: LibraryLocation

    public init(title: String, location: LibraryLocation) {
        self.title = title
        self.location = location
    }
}

/// Library change notifications.
public enum LibraryEvent: Sendable {
    /// Anything may have changed (rescan, entry point added): reload what is shown.
    case contentChanged
    /// These media changed (progress, favorite, watched).
    case mediaUpdated([String])
    /// Playlists were created, renamed, deleted or edited.
    case playlistsChanged
    /// A thumbnail finished generating for this media id.
    case thumbnailReady(String)
    /// Bookmarks of this media id changed.
    case bookmarksChanged(String)
    /// Background indexing started or stopped.
    case indexingChanged(Bool)
}

/// Native playlist membership. Metadata continues to use MediaItem.id; actions validate this snapshot.
public struct PlaylistOccurrence: Hashable, Sendable, Codable {
    public var playlistID: String
    public var position: Int
    public var revision: String
    public static func revision(for mediaIDs: [String]) -> String {
        let data = (try? JSONEncoder().encode(mediaIDs)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public init(playlistID: String, position: Int, revision: String) {
        self.playlistID = playlistID; self.position = position; self.revision = revision
    }
}
