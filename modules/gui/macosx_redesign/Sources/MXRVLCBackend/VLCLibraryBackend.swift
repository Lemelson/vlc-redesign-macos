import CoreGraphics
import Foundation
import MXRBridgeAPI
import MXRCore

@MainActor
final class VLCLibraryBackend: LibraryBackend {
    private let transport: any VLCServiceTransport
    private let events = EventChannel<LibraryEvent>()
    init(transport: any VLCServiceTransport) {
        self.transport = transport
        setThumbnailSize(Self.largestCardPixels)
        transport.addListener(self) { [weak self] service in
            guard let self else { return }
            if service == .library {
                let snapshot = self.transport.snapshot(for: service)
                // A finished thumbnail names its media; everything else reloads the page.
                for id in snapshot["thumbnails"] as? [String] ?? [] { self.events.send(.thumbnailReady(id)) }
                if snapshot["contentChanged"] as? Bool ?? true { self.events.send(.contentChanged) }
            }
            if service == .libraryError {
                let error = self.transport.snapshot(for: service).string("message") ?? "The library operation failed."
                self.transport.report(BackendOperationError.invalidInput(error))
            }
        }
    }
    /// Tells the media library how large its persisted thumbnails should be: the biggest card the
    /// interface draws (Home/grid, 316 pt) at 2x.
    static let largestCardPixels = CGSize(width: 632, height: 356)
    func setThumbnailSize(_ size: CGSize) {
        // Without a media library there is nothing to size, and an automatic call must not surface
        // an unsupported-feature error.
        guard hasMediaLibrary else { return }
        transport.command(.setThumbnailSize, service: .library, arguments: ["width": Int(size.width), "height": Int(size.height)])
    }
    private var hasMediaLibrary: Bool {
        transport.capabilities.bool("library", default: transport.capabilities.bool("hasMediaLibrary"))
    }
    var mediaCount: Int { transport.snapshot(for: .library).integer("mediaCount") }
    var isIndexing: Bool { transport.snapshot(for: .library).bool("isIndexing") }
    func page(at location: LibraryLocation, query: LibraryQuery) async throws -> LibraryPage {
        let result = try await transport.request(.page, service: .library, arguments: ["location": Self.location(location), "query": ["sort": query.sort.rawValue, "searchText": query.searchText, "offset": query.offset, "limit": query.limit]])
        return LibraryPage(location: location, entries: result.dictionaries("entries").compactMap(Self.entry), totalCount: result.integer("totalCount"), offset: query.offset, addAction: result.string("addAction").flatMap(LibraryAddAction.init(rawValue:)))
    }
    func homeSections() async throws -> [LibraryHomeSection] {
        // Home draws at most `homeLimit` entries per row; the section's "›" page (`.homeSection`) lists all.
        let limits = Dictionary(uniqueKeysWithValues: LibraryHomeSectionKind.allCases.map { ($0.rawValue, $0.homeLimit) })
        let result = try await transport.request(.homeSections, service: .library, arguments: ["limits": limits])
        return result.dictionaries("sections").compactMap { item in
            guard let kind = LibraryHomeSectionKind(rawValue: item.string("kind") ?? item.string("id") ?? "") else { return nil }
            return LibraryHomeSection(kind: kind, entries: item.dictionaries("entries").compactMap(Self.entry), destination: Self.parseLocation(item.dictionary("destination")))
        }
    }
    func breadcrumb(for location: LibraryLocation) async -> [LibraryCrumb] {
        let fallback = [LibraryCrumb(title: location.category.title, location: location.category.location)]
        guard hasMediaLibrary else { return fallback }
        do {
            let result = try await transport.request(.breadcrumb, service: .library, arguments: ["location": Self.location(location)])
            let crumbs = result.dictionaries("crumbs").compactMap { item -> LibraryCrumb? in
                guard let target = Self.parseLocation(item.dictionary("location")) else { return nil }
                return LibraryCrumb(title: item.string("title") ?? target.category.title, location: target)
            }
            if !crumbs.isEmpty { return crumbs }
        } catch { transport.log(error) }
        return fallback
    }
    func allMedia(at location: LibraryLocation, sort: LibrarySort) async throws -> [MediaItem] {
        let result = try await transport.request(.allMedia, service: .library, arguments: ["location": Self.location(location), "sort": sort.rawValue])
        return result.dictionaries("media").compactMap(VLCWire.media)
    }
    func media(id: String) async -> MediaItem? {
        guard hasMediaLibrary else { return nil }
        do { let result = try await transport.request(.media, service: .library, arguments: ["id": id]); return VLCWire.media(result.dictionary("media")) }
        catch { transport.log(error); return nil }
    }
    func setFavorite(_ favorite: Bool, mediaIDs: [String]) { transport.command(.setFavorite, service: .library, arguments: ["value": favorite, "mediaIDs": mediaIDs]) }
    func setWatched(_ watched: Bool, mediaIDs: [String]) { transport.command(.setWatched, service: .library, arguments: ["value": watched, "mediaIDs": mediaIDs]) }
    func attachSubtitle(url: URL, toMedia mediaID: String) { transport.command(.attachSubtitle, service: .library, arguments: ["url": url.absoluteString, "mediaID": mediaID]) }
    func attachAudioTrack(url: URL, toMedia mediaID: String) { transport.command(.attachAudioTrack, service: .library, arguments: ["url": url.absoluteString, "mediaID": mediaID]) }
    func clearHistory() { transport.command(.clearHistory, service: .library) }
    func createPlaylist(name: String, mediaIDs: [String], artworkURL: URL?) async throws -> Playlist {
        var args: [String: Any] = ["name": name, "mediaIDs": mediaIDs]
        if let artworkURL { args["artworkURL"] = artworkURL.absoluteString }
        let result = try await transport.request(.createPlaylist, service: .library, arguments: args)
        guard let playlist = Self.playlist(result.dictionary("playlist")) else { throw BackendOperationError.invalidInput("VLC did not return the created playlist.") }
        events.send(.playlistsChanged)
        return playlist
    }
    func appendToPlaylist(id: String, mediaIDs: [String]) async throws { _ = try await mutate(.appendToPlaylist, ["id": id, "mediaIDs": mediaIDs]) }
    @discardableResult func importFiles(urls: [URL]) async throws -> [MediaItem] {
        // VLC types an external file only when it parses it; type it now so it lists under Videos or Songs.
        let result = try await transport.request(.importFiles, service: .library, arguments: ["urls": urls.map(\.absoluteString), "kinds": urls.map { MediaItem.kind(of: $0).rawValue }])
        return result.dictionaries("media").compactMap(VLCWire.media)
    }
    func removeFromPlaylist(id: String, occurrences: [PlaylistOccurrence]) async throws {
        guard let revision = occurrences.first?.revision, occurrences.allSatisfy({ $0.playlistID == id && $0.revision == revision }) else { throw BackendOperationError.invalidInput("Reload the playlist before removing items.") }
        _ = try await mutate(.removeFromPlaylist, ["id": id, "positions": occurrences.map(\.position), "revision": revision])
    }
    func renamePlaylist(id: String, name: String) async throws { _ = try await mutate(.renamePlaylist, ["id": id, "name": name]) }
    func deletePlaylist(id: String) async throws { _ = try await mutate(.deletePlaylist, ["id": id]) }
    func setPlaylistFavorite(_ favorite: Bool, id: String) { transport.command(.setPlaylistFavorite, service: .library, arguments: ["id": id, "value": favorite]) }
    func addNetworkStream(urls: [URL], name: String?) async throws -> NetworkStream {
        var args: [String: Any] = ["urls": urls.map(\.absoluteString)]
        if let name { args["name"] = name }
        let result = try await mutate(.addNetworkStream, args)
        guard let stream = Self.stream(result.dictionary("stream")) else { throw BackendOperationError.invalidInput("VLC did not return the saved stream.") }
        return stream
    }
    func removeNetworkStream(id: String) async throws { _ = try await mutate(.removeNetworkStream, ["id": id]) }
    func renameNetworkStream(id: String, name: String) async throws { _ = try await mutate(.renameNetworkStream, ["id": id, "name": name]) }
    func addFolder(url: URL) { transport.command(.addFolder, service: .library, arguments: ["url": url.absoluteString]) }
    func removeFolder(id: String) { transport.command(.removeFolder, service: .library, arguments: ["id": id]); events.send(.contentChanged) }
    func rescan(folderID: String?) { transport.command(.rescan, service: .library, arguments: folderID.map { ["id": $0] } ?? [:]) }
    func bookmarks(mediaID: String) async -> [Bookmark] {
        guard hasMediaLibrary else { return [] }
        do { let result = try await transport.request(.bookmarks, service: .library, arguments: ["mediaID": mediaID]); return result.dictionaries("bookmarks").compactMap { Self.bookmark($0, mediaID: mediaID) } }
        catch { transport.log(error); return [] }
    }
    func addBookmark(mediaID: String, time: MediaTime, name: String) async throws -> Bookmark {
        let result = try await transport.request(.addBookmark, service: .library, arguments: ["mediaID": mediaID, "time": time.microseconds, "name": name])
        guard let bookmark = Self.bookmark(result.dictionary("bookmark"), mediaID: mediaID) else { throw BackendOperationError.invalidInput("VLC did not return the created bookmark.") }
        events.send(.bookmarksChanged(mediaID)); return bookmark
    }
    func renameBookmark(id: String, mediaID: String, name: String) async throws {
        _ = try await transport.request(.renameBookmark, service: .library, arguments: ["id": id, "mediaID": mediaID, "name": name]); events.send(.bookmarksChanged(mediaID))
    }
    func removeBookmark(id: String, mediaID: String) async throws {
        _ = try await transport.request(.removeBookmark, service: .library, arguments: ["id": id, "mediaID": mediaID]); events.send(.bookmarksChanged(mediaID))
    }
    func addListener(_ owner: AnyObject, handler: @escaping @MainActor (LibraryEvent) -> Void) { events.add(owner, handler: handler) }
    private func mutate(_ name: MXRBridgeRequest, _ arguments: [String: Any]) async throws -> [String: Any] { let result = try await transport.request(name, service: .library, arguments: arguments); events.send(.playlistsChanged); return result }
    static func location(_ location: LibraryLocation) -> [String: Any] {
        switch location {
        case .homeSection(let kind): ["kind":"homeSection", "id":kind.rawValue]
        case .home: ["kind":"home"]; case .videos: ["kind":"videos"]; case .music: ["kind":"music"]; case .songs: ["kind":"songs"]; case .albums: ["kind":"albums"]; case .artists: ["kind":"artists"]; case .genres: ["kind":"genres"]; case .network: ["kind":"network"]; case .playlists: ["kind":"playlists"]; case .recent: ["kind":"recent"]
        case .folder(let id): ["kind":"folder","id":id]; case .album(let id): ["kind":"album","id":id]; case .artist(let id): ["kind":"artist","id":id]; case .genre(let id): ["kind":"genre","id":id]; case .playlist(let id): ["kind":"playlist","id":id]; case .show(let id): ["kind":"show","id":id]; case .stream(let id): ["kind":"stream","id":id]
        }
    }
    static func parseLocation(_ value: [String: Any]) -> LibraryLocation? {
        let id = value.string("id") ?? ""
        switch value.string("kind") {
        case "homeSection": return LibraryHomeSectionKind(rawValue: id).map(LibraryLocation.homeSection)
        case "home": return .home; case "videos": return .videos; case "music": return .music; case "songs": return .songs; case "albums": return .albums; case "artists": return .artists; case "genres": return .genres; case "network": return .network; case "playlists": return .playlists; case "recent": return .recent
        case "folder": return .folder(id); case "album": return .album(id); case "artist": return .artist(id); case "genre": return .genre(id); case "playlist": return .playlist(id); case "show": return .show(id); case "stream": return .stream(id); default: return nil
        }
    }
    static func playlist(_ x: [String: Any]) -> Playlist? { guard let id = x.string("id") else { return nil }; let length = x.int64("duration", default: -1); return Playlist(id: id, name: x.string("name") ?? "Playlist", itemCount: x.integer("itemCount"), duration: length >= 0 ? MediaTime(microseconds: length) : nil, artworkURL: x.url("artworkURL"), isFavorite: x.bool("isFavorite")) }
    static func stream(_ x: [String: Any]) -> NetworkStream? { guard let id = x.string("id") else { return nil }; return NetworkStream(id: id, name: x.string("name") ?? "Stream", urls: (x["urls"] as? [String] ?? []).compactMap(URL.init(string:)), itemCount: x["itemCount"] == nil ? nil : x.integer("itemCount")) }
    static func bookmark(_ x: [String: Any], mediaID: String) -> Bookmark? { guard let id = x.string("id") else { return nil }; return Bookmark(id: id, mediaID: x.string("mediaID") ?? mediaID, name: x.string("name") ?? "Bookmark", time: MediaTime(microseconds: x.int64("time"))) }
    static func entry(_ x: [String: Any]) -> LibraryEntry? {
        let id = x.string("id") ?? "", name = x.string("name") ?? x.string("title") ?? ""
        switch x.string("type") {
        case "media":
            guard var media = VLCWire.media(x.dictionary("media")) else { return nil }
            let occurrence = x.dictionary("media").dictionary("playlistOccurrence")
            if let playlistID = occurrence.string("playlistID"), let revision = occurrence.string("revision") {
                media.playlistOccurrence = PlaylistOccurrence(playlistID: playlistID, position: occurrence.integer("position"), revision: revision)
            }
            return .media(media)
        case "folder": return .folder(LibraryFolder(id: id, name: name, url: x.url("url"), itemCount: x["itemCount"] == nil ? nil : x.integer("itemCount"), contentKind: MediaKind(rawValue: x.string("kind") ?? "video") ?? .video, isEntryPoint: x.bool("isEntryPoint")))
        case "playlist": return playlist(x).map(LibraryEntry.playlist)
        case "album": return .album(Album(id: id, title: name, artist: x.string("artist"), year: x["year"] == nil ? nil : x.integer("year"), trackCount: x.integer("trackCount"), artworkURL: x.url("artworkURL")))
        case "artist": return .artist(Artist(id: id, name: name, albumCount: x.integer("albumCount"), trackCount: x.integer("trackCount"), artworkURL: x.url("artworkURL")))
        case "genre": return .genre(Genre(id: id, name: name, trackCount: x.integer("trackCount")))
        case "show": return .show(Show(id: id, name: name, seasonCount: x.integer("seasonCount"), episodeCount: x.integer("episodeCount"), artworkURL: x.url("artworkURL")))
        case "stream": return stream(x).map(LibraryEntry.stream)
        case "link": guard let target = parseLocation(x.dictionary("destination")) else { return nil }; return .link(LibraryLink(title: name, destination: target, iconName: x.string("iconName") ?? "folder"))
        default: return VLCWire.media(x).map(LibraryEntry.media)
        }
    }
}
