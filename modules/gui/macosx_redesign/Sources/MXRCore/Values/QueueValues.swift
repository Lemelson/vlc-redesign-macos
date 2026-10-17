import Foundation

/// One entry of the play queue (`vlc_playlist_item_t`). The same media may appear twice with different ids.
public struct QueueItem: Identifiable, Hashable, Sendable {
    /// Unique within the session (the bridge uses the playlist item's `id`).
    public var id: UInt64
    public var media: MediaItem

    public init(id: UInt64, media: MediaItem) {
        self.id = id
        self.media = media
    }
}

/// Repeat mode (`enum vlc_playlist_playback_repeat`). The queue's repeat button cycles off → all → one.
public enum RepeatMode: String, Sendable, Codable, Hashable, CaseIterable {
    case off
    case all
    /// Repeat the current item (`VLC_PLAYLIST_PLAYBACK_REPEAT_CURRENT`).
    case one

    /// The next mode when the repeat button is clicked.
    public var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Playback order (`enum vlc_playlist_playback_order`). Random = the shuffle button.
public enum PlaybackOrder: String, Sendable, Codable, Hashable {
    case normal
    case random
}

/// What happens when an item ends (`enum vlc_playlist_media_stopped_action`; Settings ▸ Playback
/// "When playback finishes").
public enum MediaStoppedAction: String, Sendable, Codable, Hashable, CaseIterable {
    case `continue`
    case pause
    case stop
    case exit
}

/// Queue sort keys (`enum vlc_playlist_sort_key`).
public enum QueueSortKey: String, Sendable, Codable, Hashable, CaseIterable {
    case title, duration, artist, album, albumArtist, genre, date, trackNumber, discNumber, url, rating

    public var title: String {
        switch self {
        case .title: "Title"
        case .duration: "Duration"
        case .artist: "Artist"
        case .album: "Album"
        case .albumArtist: "Album Artist"
        case .genre: "Genre"
        case .date: "Date"
        case .trackNumber: "Track Number"
        case .discNumber: "Disc Number"
        case .url: "URL"
        case .rating: "Rating"
        }
    }
}

/// A queue sort request.
public struct QueueSort: Hashable, Sendable, Codable {
    public var key: QueueSortKey
    public var ascending: Bool

    public init(key: QueueSortKey, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }
}
