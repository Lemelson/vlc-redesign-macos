import Foundation

/// Queue change notifications.
public enum QueueEvent: Sendable, Hashable {
    /// Items were added, removed, moved, updated or sorted.
    case items
    /// The current item changed.
    case current
    /// Repeat mode, order or stop action changed.
    case playbackMode
}

/// The play queue (`vlc_playlist_t`): what plays next (S22). Not saved playlists, which are in the library.
@MainActor
public protocol PlayQueueBackend: AnyObject {
    var items: [QueueItem] { get }
    /// Index of the current item in `items`, nil when none.
    var currentIndex: Int? { get }
    var repeatMode: RepeatMode { get }
    var order: PlaybackOrder { get }
    var mediaStoppedAction: MediaStoppedAction { get }
    var hasNext: Bool { get }
    var hasPrevious: Bool { get }

    /// Starts playing the item at `index`.
    func play(at index: Int)
    /// Starts or resumes playback of the current item (`vlc_playlist_Start`).
    func start()
    func next()
    func previous()
    /// Inserts media at `index` (nil = append). Returns nothing; observe `.items`.
    func insert(_ media: [MediaItem], at index: Int?)
    /// Moves the items with `ids` so the first lands at `index` (indexes before the move).
    func move(ids: [QueueItem.ID], to index: Int)
    func remove(ids: [QueueItem.ID])
    func clear()
    func sort(_ sort: QueueSort)
    func setRepeatMode(_ mode: RepeatMode)
    func setOrder(_ order: PlaybackOrder)
    func setMediaStoppedAction(_ action: MediaStoppedAction)

    /// Set once by ``AppModel``: per-media settings needed when an input opens (per-show track
    /// preferences). Call it on the main actor for each media when it is inserted, and again before an
    /// item starts if the backend can; pass a non-empty result as per-input options
    /// (`:audio-track=`, `:audio-language=`, `:sub-track=`, `:sub-language=`).
    var startOptionsProvider: (@MainActor (MediaItem) -> MediaStartOptions?)? { get set }

    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (QueueEvent) -> Void)
}

/// Transitional default (ignores the provider) so queue backends written before it existed compile.
extension PlayQueueBackend {
    public var startOptionsProvider: (@MainActor (MediaItem) -> MediaStartOptions?)? {
        get { nil }
        set {}
    }
}

/// The media library (`vlc_medialibrary_t`). Queries are paged and async (run off main by the bridge).
@MainActor
public protocol LibraryBackend: AnyObject {
    /// A page of entries at `location`.
    func page(at location: LibraryLocation, query: LibraryQuery) async throws -> LibraryPage
    /// A synchronously available page (cache or scripted data), used to avoid an empty first frame.
    /// The default returns nil.
    func cachedPage(at location: LibraryLocation, query: LibraryQuery) -> LibraryPage?
    /// Home sections (Continue Watching, Listen Again, …).
    func homeSections() async throws -> [LibraryHomeSection]
    /// Synchronously available Home sections; default nil.
    func cachedHomeSections() -> [LibraryHomeSection]?
    /// Breadcrumb from the category root to `location` ("Videos ▸ Shows ▸ The Wand ▸ S01").
    func breadcrumb(for location: LibraryLocation) async -> [LibraryCrumb]
    /// Synchronously available breadcrumb; default nil.
    func cachedBreadcrumb(for location: LibraryLocation) -> [LibraryCrumb]?
    /// All media of a container location, in display order (play a folder, add a folder to the queue).
    func allMedia(at location: LibraryLocation, sort: LibrarySort) async throws -> [MediaItem]
    /// A media by id.
    func media(id: String) async -> MediaItem?
    /// Total number of media in the library (Home "110 items").
    var mediaCount: Int { get }
    /// True while the library is indexing.
    var isIndexing: Bool { get }

    // MARK: Media state
    func setFavorite(_ favorite: Bool, mediaIDs: [String])
    func setWatched(_ watched: Bool, mediaIDs: [String])
    /// Attaches a subtitle file to a media for future playback (`VLC_ML_MEDIA_ADD_EXTERNAL_MRL`).
    func attachSubtitle(url: URL, toMedia mediaID: String)
    /// Attaches an audio file to a media as an external audio track of every later playback
    /// (`VLC_ML_FILE_TYPE_SOUNDTRACK`; the queue loads it as a slave, Edit/Add Audio Tracks).
    func attachAudioTrack(url: URL, toMedia mediaID: String)
    func clearHistory()

    // MARK: Playlists
    func createPlaylist(name: String, mediaIDs: [String], artworkURL: URL?) async throws -> Playlist
    func appendToPlaylist(id: String, mediaIDs: [String]) async throws
    /// Removes rows of a playlist. Each occurrence names a storage position in the playlist revision
    /// it was read from; a backend rejects the whole request if the playlist changed since.
    func removeFromPlaylist(id: String, occurrences: [PlaylistOccurrence]) async throws
    /// Adds files to the library without a folder scan; returns them as the library lists them.
    @discardableResult func importFiles(urls: [URL]) async throws -> [MediaItem]
    func renamePlaylist(id: String, name: String) async throws
    func deletePlaylist(id: String) async throws
    func setPlaylistFavorite(_ favorite: Bool, id: String)

    // MARK: Network streams
    /// Saves streams to the Network category. Several URLs or an m3u become a stream playlist named `name`.
    func addNetworkStream(urls: [URL], name: String?) async throws -> NetworkStream
    func removeNetworkStream(id: String) async throws
    /// Renames a saved network collection (row menu "Rename").
    func renameNetworkStream(id: String, name: String) async throws

    // MARK: Folders
    /// Adds a folder to index (entry point).
    func addFolder(url: URL)
    func removeFolder(id: String)
    /// Rescans a folder, or everything when `id` is nil ("Resync").
    func rescan(folderID: String?)

    // MARK: Bookmarks
    func bookmarks(mediaID: String) async -> [Bookmark]
    /// Synchronously available bookmarks; default nil.
    func cachedBookmarks(mediaID: String) -> [Bookmark]?
    func addBookmark(mediaID: String, time: MediaTime, name: String) async throws -> Bookmark
    func renameBookmark(id: String, mediaID: String, name: String) async throws
    func removeBookmark(id: String, mediaID: String) async throws

    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (LibraryEvent) -> Void)
}

extension LibraryBackend {
    public func attachAudioTrack(url: URL, toMedia mediaID: String) {}
    public func importFiles(urls: [URL]) async throws -> [MediaItem] { throw BackendOperationError.unsupported("Import files into library") }
    public func cachedPage(at location: LibraryLocation, query: LibraryQuery) -> LibraryPage? { nil }
    public func cachedHomeSections() -> [LibraryHomeSection]? { nil }
    public func cachedBreadcrumb(for location: LibraryLocation) -> [LibraryCrumb]? { nil }
    public func cachedBookmarks(mediaID: String) -> [Bookmark]? { nil }
    public func renameNetworkStream(id: String, name: String) async throws { throw BackendOperationError.unsupported("Renaming a saved stream") }
}

/// Media-source change notifications (discovery is asynchronous: shares and UPnP servers appear later).
public enum MediaSourceEvent: Sendable, Hashable {
    /// The list of sources of a category changed.
    case sourcesChanged(MediaSourceCategory)
    /// Children of a node changed (`nodeID` nil = the source's root); re-query ``MediaSourceBackend/children(of:in:)``.
    case childrenChanged(sourceID: String, nodeID: String?)
}

/// Network and device browsing (`vlc_media_source_provider`): LAN shares, UPnP, SAP.
@MainActor
public protocol MediaSourceBackend: AnyObject {
    /// Starts discovering a category's sources (network discovery is lazy, D039). Idempotent.
    func startDiscovery(in category: MediaSourceCategory)
    /// Available sources of a category: a snapshot read, never starts discovery.
    func sources(in category: MediaSourceCategory) -> [MediaSourceInfo]
    /// Children of a node; `node` nil = the source's root.
    func children(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode]
    /// Refreshes a node from its source, including reparsing directory listings.
    /// Ordinary change notifications should use `children` to read the latest cache.
    func refreshChildren(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode]
    /// Registers a listener (`vlc_media_tree_listener`: `on_children_added/removed`).
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MediaSourceEvent) -> Void)
}

/// Transitional default (never notifies) so backends written before the listener existed compile.
extension MediaSourceBackend {
    /// Static sources (mock, tests) need no discovery.
    public func startDiscovery(in category: MediaSourceCategory) {}
    public func refreshChildren(of node: MediaSourceNode?, in source: MediaSourceInfo) async throws -> [MediaSourceNode] {
        try await children(of: node, in: source)
    }
    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (MediaSourceEvent) -> Void) {}
}
