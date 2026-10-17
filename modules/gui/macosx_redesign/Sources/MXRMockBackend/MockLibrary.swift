import Foundation
import MXRCore

/// Errors of the mock library.
public enum MockLibraryError: Error, Equatable {
    case notFound
    case invalidName
}

/// Scripted media library. Every query is answered synchronously as well (`cached…`), so
/// snapshots render populated on the first frame.
///
/// It models the same domain as the VLC backend (MXRLibraryServices.m): folder trees under entry
/// points, the Music links, "+" rows per location, non-empty Home sections with destinations, and
/// media-library progress semantics (a watched item has a play count and no partial position).
/// `MockLibraryContractTests` holds both to that contract; there are no per-capture data overrides.
@MainActor
public final class MockLibrary: LibraryBackend {
    /// The data (mutable through the protocol's write methods).
    public internal(set) var isIndexing = false
    var db: MockDatabase
    private let events = EventChannel<LibraryEvent>()
    private var importedIDs: [String] = []

    init(db: MockDatabase) {
        self.db = db
    }

    /// Media by id, synchronously (scenarios and tests).
    public func mediaItem(id: String) -> MediaItem? { db.media[id] }

    public var mediaCount: Int { db.media.count }

    // MARK: Queries

    public func page(at location: LibraryLocation, query: LibraryQuery) async throws -> LibraryPage {
        makePage(at: location, query: query)
    }

    public func cachedPage(at location: LibraryLocation, query: LibraryQuery) -> LibraryPage? {
        makePage(at: location, query: query)
    }

    public func homeSections() async throws -> [LibraryHomeSection] { makeHomeSections() }
    public func cachedHomeSections() -> [LibraryHomeSection]? { makeHomeSections() }
    public func breadcrumb(for location: LibraryLocation) async -> [LibraryCrumb] { db.breadcrumb(for: location) }
    public func cachedBreadcrumb(for location: LibraryLocation) -> [LibraryCrumb]? { db.breadcrumb(for: location) }

    public func allMedia(at location: LibraryLocation, sort: LibrarySort) async throws -> [MediaItem] {
        MockDatabase.sort(db.allMedia(at: location).map { .media($0) }, by: sort, order: db.mediaOrder).compactMap(\.media)
    }

    public func media(id: String) async -> MediaItem? { db.media[id] }

    private func makeHomeSections() -> [LibraryHomeSection] { db.homeSections() }

    private func makePage(at location: LibraryLocation, query: LibraryQuery) -> LibraryPage {
        var (all, add) = db.sortedEntries(at: location, sort: query.sort, search: query.searchText)
        if location == .videos || location == .songs || (location == .home && !query.searchText.isEmpty) {
            let known = Set(all.compactMap(\.media?.id))
            let imported = importedIDs.compactMap { db.media[$0] }.filter {
                !known.contains($0.id) && (location == .home || $0.kind == (location == .songs ? .audio : .video))
                && (query.searchText.isEmpty || $0.listTitle.localizedStandardContains(query.searchText))
            }
            all = MockDatabase.sort(all + imported.map(LibraryEntry.media), by: query.sort, order: db.mediaOrder)
        }
        let start = min(max(query.offset, 0), all.count)
        let end = min(start + max(query.limit, 0), all.count)
        return LibraryPage(location: location, entries: Array(all[start..<end]), totalCount: all.count, offset: start, addAction: add)
    }

    // MARK: Media state

    public func setFavorite(_ favorite: Bool, mediaIDs: [String]) {
        for id in mediaIDs { db.update(id) { $0.isFavorite = favorite } }
        events.send(.mediaUpdated(mediaIDs))
    }

    public func setWatched(_ watched: Bool, mediaIDs: [String]) {
        for id in mediaIDs {
            db.update(id) { item in
                // vlc_ml_media_set_played: the play count changes and the saved position is cleared.
                item.playCount = watched ? max(item.playCount, 1) : 0
                item.progress = nil
            }
        }
        events.send(.mediaUpdated(mediaIDs))
    }

    /// Records playback progress (called by the mock when media end or stop).
    func recordProgress(mediaID: String, progress: Double, finished: Bool) {
        db.update(mediaID) { item in
            item.lastPlayedDate = mockReferenceDate
            if finished {
                item.playCount += 1
                item.progress = nil
            } else {
                item.progress = progress
            }
        }
        events.send(.mediaUpdated([mediaID]))
    }

    public func attachSubtitle(url: URL, toMedia mediaID: String) {
        events.send(.mediaUpdated([mediaID]))
    }

    /// Audio files attached per media id (Edit/Add Audio Tracks), in attach order.
    public private(set) var attachedAudioTracks: [String: [URL]] = [:]

    public func attachAudioTrack(url: URL, toMedia mediaID: String) {
        attachedAudioTracks[mediaID, default: []].append(url)
        events.send(.mediaUpdated([mediaID]))
    }

    public func clearHistory() {
        for id in db.mediaOrder { db.update(id) { $0.lastPlayedDate = nil } }
        events.send(.contentChanged)
    }

    // MARK: Playlists

    public func createPlaylist(name: String, mediaIDs: [String], artworkURL: URL?) async throws -> Playlist {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw MockLibraryError.invalidName }
        let mediaIDs = try resolvePlaylistMediaIDs(mediaIDs)
        let id = db.makeID("pl")
        let order = (db.playlists.map(\.addedOrder).max() ?? 0) + 1
        db.playlists.append(MockPlaylist(playlist: Playlist(id: id, name: trimmed, artworkURL: artworkURL), mediaIDs: mediaIDs, addedOrder: order))
        db.refreshPlaylistStats(db.playlists.count - 1)
        events.send(.playlistsChanged)
        return db.playlists[db.playlists.count - 1].playlist
    }

    public func appendToPlaylist(id: String, mediaIDs: [String]) async throws {
        guard let index = db.playlists.firstIndex(where: { $0.playlist.id == id }) else { throw MockLibraryError.notFound }
        db.playlists[index].mediaIDs += try resolvePlaylistMediaIDs(mediaIDs)
        db.refreshPlaylistStats(index)
        events.send(.playlistsChanged)
    }

    /// File-picker items use their absolute URL as the id until imported into the library.
    private func resolvePlaylistMediaIDs(_ ids: [String]) throws -> [String] {
        let items = try ids.map { id -> MediaItem in
            if let registered = db.media[id] { return registered }
            guard !id.hasPrefix("ml:"), let url = URL(string: id), url.scheme != nil else {
                throw MockLibraryError.notFound
            }
            return MediaItem(url: url)
        }
        // Validate the whole request before changing the database. Repeated playlist positions
        // reference one registered item while retaining the caller's requested ordering.
        for item in items where db.media[item.id] == nil {
            db.media[item.id] = item
            db.mediaOrder.append(item.id)
        }
        return items.map(\.id)
    }

    @discardableResult public func importFiles(urls: [URL]) async throws -> [MediaItem] {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { throw MockLibraryError.notFound }
        let ids = try resolvePlaylistMediaIDs(urls.map(\.absoluteString))
        for id in ids where !importedIDs.contains(id) { importedIDs.append(id) }
        events.send(.contentChanged)
        return ids.compactMap { db.media[$0] }
    }
    public func removeFromPlaylist(id: String, occurrences: [PlaylistOccurrence]) async throws {
        guard let index = db.playlists.firstIndex(where: { $0.playlist.id == id }) else { throw MockLibraryError.notFound }
        let mediaIDs = db.playlists[index].mediaIDs
        guard occurrences.allSatisfy({ $0.playlistID == id && $0.revision == PlaylistOccurrence.revision(for: mediaIDs) && mediaIDs.indices.contains($0.position) }) else { throw MockLibraryError.notFound }
        for position in Set(occurrences.map(\.position)).sorted(by: >) {
            db.playlists[index].mediaIDs.remove(at: position)
        }
        db.refreshPlaylistStats(index)
        events.send(.playlistsChanged)
    }

    public func renamePlaylist(id: String, name: String) async throws {
        guard let index = db.playlists.firstIndex(where: { $0.playlist.id == id }) else { throw MockLibraryError.notFound }
        db.playlists[index].playlist.name = name
        events.send(.playlistsChanged)
    }

    public func deletePlaylist(id: String) async throws {
        db.playlists.removeAll { $0.playlist.id == id }
        events.send(.playlistsChanged)
    }

    /// Figma's compact Home (S40, 1106:5633) ranks the playlists "Fav Episodes", "Coolest Songs" and
    /// "Anime Playlist", which Figma's own Playlists page (858:5374: Cool Songs, Anime to Watch) does
    /// not have. This gallery fixture replaces the playlists with those three, filled so that the
    /// backend's ranking (recently played items per playlist, ties in storage order) yields Figma's
    /// order: 7, 3 and 3 played items. Home sections are still computed, not scripted.
    public func useFigmaHomePlaylists() {
        let episodes = (1...7).map { MockDatabase.wandID(season: 1, episode: $0) }
        let songs = [MockDatabase.untangleID, MockDatabase.moonlightID, MockDatabase.blackBirdID]
        let anime = (4...9).map { "ml:kaze-e" + String(format: "%02d", $0) }
        db.playlists = [("pl-fav-episodes", "Fav Episodes", episodes), ("pl-coolest-songs", "Coolest Songs", songs),
                        ("pl-anime-playlist", "Anime Playlist", anime)].enumerated().map { order, playlist in
            MockPlaylist(playlist: Playlist(id: playlist.0, name: playlist.1), mediaIDs: playlist.2.filter { db.media[$0] != nil }, addedOrder: order)
        }
        for index in db.playlists.indices { db.refreshPlaylistStats(index) }
        events.send(.playlistsChanged)
    }

    /// Figma's compact Home (S40, 1106:5633) lists the Videos entry points Shows, Films and Anime as
    /// Frequently Visited Folders. The backends rank the folders that hold recently played media
    /// (here S01, Kaze no Tabi, My Songs), and no play history of this library ranks the entry points,
    /// which hold no media of their own. This gallery fixture lists those three folders instead.
    public func useFigmaHomeFolders() {
        db.figmaHomeFolderIDs = ["shows", "films", "anime"]
        events.send(.contentChanged)
    }

    public func setPlaylistFavorite(_ favorite: Bool, id: String) {
        guard let index = db.playlists.firstIndex(where: { $0.playlist.id == id }) else { return }
        db.playlists[index].playlist.isFavorite = favorite
        events.send(.playlistsChanged)
    }

    // MARK: Network streams

    public func addNetworkStream(urls: [URL], name: String?) async throws -> NetworkStream {
        guard let first = urls.first else { throw MockLibraryError.invalidName }
        let id = db.makeID("stream")
        let title = name ?? (first.deletingPathExtension().lastPathComponent.isEmpty ? first.host ?? "Network Stream" : first.deletingPathExtension().lastPathComponent)
        // Playlist files are expanded into their entries when saved (the VLC backend preparses them).
        let isPlaylist = ["m3u", "m3u8", "pls", "xspf"].contains(first.pathExtension.lowercased())
        let stream = isPlaylist && urls.count == 1 ? MockDatabase.expandedStream(id: id, name: title, channels: 12)
            : NetworkStream(id: id, name: title, urls: urls, itemCount: urls.count)
        let order = (db.streams.map(\.addedOrder).max() ?? 0) + 1
        db.streams.append(MockStream(stream: stream, addedOrder: order))
        events.send(.playlistsChanged)
        return stream
    }

    public func removeNetworkStream(id: String) async throws {
        db.streams.removeAll { $0.stream.id == id }
        events.send(.playlistsChanged)
    }

    public func renameNetworkStream(id: String, name: String) async throws {
        guard let index = db.streams.firstIndex(where: { $0.stream.id == id }) else { throw MockLibraryError.notFound }
        db.streams[index].stream.name = name
        events.send(.playlistsChanged)
    }

    // MARK: Folders

    public func addFolder(url: URL) {
        let id = db.makeID("folder")
        db.folders[id] = MockFolder(folder: LibraryFolder(id: id, name: url.lastPathComponent, url: url, itemCount: 0, contentKind: .video, isEntryPoint: true))
        db.videoRoots.append(id)
        events.send(.contentChanged)
    }

    public func removeFolder(id: String) {
        db.videoRoots.removeAll { $0 == id }
        db.audioRoots.removeAll { $0 == id }
        events.send(.contentChanged)
    }

    public func rescan(folderID: String?) {
        isIndexing = true
        events.send(.indexingChanged(true))
        isIndexing = false
        events.send(.indexingChanged(false))
        events.send(.contentChanged)
    }

    // MARK: Bookmarks

    public func bookmarks(mediaID: String) async -> [Bookmark] { db.bookmarks[mediaID] ?? [] }
    public func cachedBookmarks(mediaID: String) -> [Bookmark]? { db.bookmarks[mediaID] ?? [] }

    public func addBookmark(mediaID: String, time: MediaTime, name: String) async throws -> Bookmark {
        let bookmark = Bookmark(id: db.makeID("bm"), mediaID: mediaID, name: name, time: time)
        db.bookmarks[mediaID, default: []].append(bookmark)
        events.send(.bookmarksChanged(mediaID))
        return bookmark
    }

    public func renameBookmark(id: String, mediaID: String, name: String) async throws {
        guard let index = db.bookmarks[mediaID]?.firstIndex(where: { $0.id == id }) else { throw MockLibraryError.notFound }
        db.bookmarks[mediaID]?[index].name = name
        events.send(.bookmarksChanged(mediaID))
    }

    public func removeBookmark(id: String, mediaID: String) async throws {
        db.bookmarks[mediaID]?.removeAll { $0.id == id }
        events.send(.bookmarksChanged(mediaID))
    }

    public func addListener(_ owner: AnyObject, handler: @escaping @MainActor (LibraryEvent) -> Void) {
        events.add(owner, handler: handler)
    }
}
