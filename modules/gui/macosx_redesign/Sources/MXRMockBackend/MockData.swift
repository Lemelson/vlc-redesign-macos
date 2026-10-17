import Foundation
import MXRCore

/// A stable (process-independent) hash for deterministic mock data (FNV-1a, 64-bit).
func stableHash(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
}

/// A small deterministic pseudo-random generator (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A folder of the mock library.
struct MockFolder {
    var folder: LibraryFolder
    var parentID: String?
    var subfolderIDs: [String] = []
    var mediaIDs: [String] = []
    /// Folders that contain other folders show the "+ Add" row (as in the Figma panels).
    var showsAddRow: Bool { !subfolderIDs.isEmpty }
}

struct MockPlaylist {
    var playlist: Playlist
    var mediaIDs: [String]
    var addedOrder: Int
}

struct MockStream {
    var stream: NetworkStream
    var addedOrder: Int
    /// A default collection the library seeds on first launch (Podcasts, Radio); Home lists it
    /// under Latest Streams only after it was played, as the VLC backend does.
    var seeded = false
}

/// Fixed reference date of the mock data (2026-10-12 12:00 UTC, the day the Figma file was published).
let mockReferenceDate = Date(timeIntervalSince1970: 1_791_806_400)

/// The scripted library: the Figma content ("The Wand" S01 with watched states, "My Songs" by
/// juxtopposed, "Cool Songs" / "Anime to Watch", Podcasts/Radio, …), padded to 110 media like the
/// Home header.
struct MockDatabase {
    var media: [String: MediaItem] = [:]
    /// Insertion order of media ids.
    var mediaOrder: [String] = []
    var folders: [String: MockFolder] = [:]
    var videoRoots: [String] = []
    var audioRoots: [String] = []
    var playlists: [MockPlaylist] = []
    var streams: [MockStream] = []
    var albums: [Album] = []
    var albumTracks: [String: [String]] = [:]
    var artists: [Artist] = []
    var genres: [Genre] = []
    var genreTracks: [String: [String]] = [:]
    var shows: [Show] = []
    var showEpisodes: [String: [String]] = [:]
    var bookmarks: [String: [Bookmark]] = [:]
    var chapters: [String: [Chapter]] = [:]
    var nextID = 1000
    /// Gallery fixture only (``MockLibrary/useFigmaHomeFolders()``): the folders Home's Frequently
    /// Visited Folders lists in place of the play-history ranking. `nil` everywhere else.
    var figmaHomeFolderIDs: [String]?

    // MARK: Well-known ids

    static func wandID(season: Int, episode: Int) -> String { "ml:wand-s\(String(format: "%02d", season))e\(String(format: "%02d", episode))" }
    static let dontBlinkID = "ml:film-dont-blink"
    static let untangleID = "ml:song-untangle"
    static let moonlightID = "ml:song-moonlight"
    static let blackBirdID = "ml:song-black-bird"
    static let wandS01Folder = "wand-s01"
    static let mySongsFolder = "my-songs"
    static let showsFolder = "shows"
    static let wandFolder = "wand"

    /// Episode lengths of The Wand S01 (E04 = 00:25:40 and E11–E14 match the Figma player/queue).
    static let wandS01Durations: [MediaTime] = [
        .hms(0, 24, 12), .hms(0, 23, 48), .hms(0, 24, 30), .hms(0, 25, 40), .hms(0, 23, 55),
        .hms(0, 24, 5), .hms(0, 22, 58), .hms(0, 24, 44), .hms(0, 23, 20), .hms(0, 24, 1),
        .hms(0, 23, 6), .hms(0, 24, 18), .hms(0, 25, 0), .hms(0, 22, 35), .hms(0, 26, 10),
    ]

    // MARK: Building

    static func make() -> MockDatabase {
        var db = MockDatabase()
        db.build()
        return db
    }

    /// First launch: no folders, no history; the Network category holds the seeded defaults.
    static func makeEmpty() -> MockDatabase {
        var db = MockDatabase()
        db.seedDefaultStreams()
        return db
    }

    private mutating func seedDefaultStreams() {
        streams = [
            MockStream(stream: NetworkStream(id: "stream-podcasts", name: "Podcasts", urls: [
                URL(string: "https://podcasts.example.com/feed-1.mp3")!, URL(string: "https://podcasts.example.com/feed-2.mp3")!,
            ], itemCount: 2), addedOrder: 0, seeded: true),
            MockStream(stream: NetworkStream(id: "stream-radio", name: "Radio", urls: [
                URL(string: "https://radio.example.com/lofi.mp3")!, URL(string: "https://radio.example.com/jazz.aac")!,
                URL(string: "https://radio.example.com/news.mp3")!,
            ], itemCount: 3), addedOrder: 1, seeded: true),
        ]
    }

    private static func fileMRL(_ path: String) -> String {
        URL(fileURLWithPath: "/Users/Shared/Media/" + path).absoluteString
    }

    private mutating func addFolder(_ id: String, _ name: String, parent: String?, kind: MediaKind, path: String) {
        let folder = LibraryFolder(id: id, name: name, url: URL(fileURLWithPath: "/Users/Shared/Media/" + path, isDirectory: true),
                                   itemCount: 0, contentKind: kind, isEntryPoint: parent == nil)
        folders[id] = MockFolder(folder: folder, parentID: parent)
        if let parent {
            folders[parent]?.subfolderIDs.append(id)
        } else if kind == .audio {
            audioRoots.append(id)
        } else {
            videoRoots.append(id)
        }
    }

    private mutating func addMedia(_ item: MediaItem, folder folderID: String) {
        var item = item
        if let folder = folders[folderID] {
            item.folder = FolderReference(id: folderID, name: folder.folder.name)
        }
        item.addedDate = mockReferenceDate.addingTimeInterval(TimeInterval(mediaOrder.count - 200) * 3_600)
        media[item.id] = item
        mediaOrder.append(item.id)
        folders[folderID]?.mediaIDs.append(item.id)
    }

    private mutating func build() {
        // Video entry points (Figma "Videos": Shows, Films, Anime).
        addFolder(Self.showsFolder, "Shows", parent: nil, kind: .video, path: "Videos/Shows")
        addFolder("films", "Films", parent: nil, kind: .video, path: "Videos/Films")
        addFolder("anime", "Anime", parent: nil, kind: .video, path: "Videos/Anime")
        addFolder(Self.wandFolder, "The Wand", parent: Self.showsFolder, kind: .video, path: "Videos/Shows/The Wand")
        addFolder(Self.wandS01Folder, "S01", parent: Self.wandFolder, kind: .video, path: "Videos/Shows/The Wand/S01")
        addFolder("wand-s02", "S02", parent: Self.wandFolder, kind: .video, path: "Videos/Shows/The Wand/S02")

        // The Wand S01: E01–E04 watched, E05–E07 in progress (Continue Watching), the rest new.
        // Positions follow the media library: a partial position is a progress; a completed play
        // increments the play count and clears the position (VLC stores -1, the bridge sends none).
        // Bar lengths measured on Figma Continue Watching (S43 6261:15093, 2x render): 44, 10 and 10 px.
        let progressS01: [Int: Double] = [5: 0.072, 6: 0.016, 7: 0.016]
        for episode in 1...15 {
            let name = "The_Wand_S01E\(String(format: "%02d", episode)).mp4"
            var item = MediaItem(
                id: Self.wandID(season: 1, episode: episode), mrl: Self.fileMRL("Videos/Shows/The Wand/S01/" + name),
                title: name, fileName: name, kind: .video, duration: Self.wandS01Durations[episode - 1],
                episode: EpisodeInfo(showID: "show-wand", showName: "The Wand", season: 1, episode: episode),
                videoSize: CGSize(width: 1920, height: 1080))
            if episode <= 4 {
                item.playCount = 1
                item.lastPlayedDate = mockReferenceDate.addingTimeInterval(TimeInterval(-86_400 * (5 - episode)))
            } else if let progress = progressS01[episode] {
                item.progress = progress
                item.lastPlayedDate = mockReferenceDate.addingTimeInterval(TimeInterval(-3_600 * (episode - 4)))
            }
            addMedia(item, folder: Self.wandS01Folder)
        }
        for episode in 1...15 {
            let name = "The_Wand_S02E\(String(format: "%02d", episode)).mp4"
            let seconds = 22 * 60 + Int(stableHash(name) % 300)
            addMedia(MediaItem(
                id: Self.wandID(season: 2, episode: episode), mrl: Self.fileMRL("Videos/Shows/The Wand/S02/" + name),
                title: name, fileName: name, kind: .video, duration: .seconds(Double(seconds)),
                episode: EpisodeInfo(showID: "show-wand", showName: "The Wand", season: 2, episode: episode),
                videoSize: CGSize(width: 1920, height: 1080)), folder: "wand-s02")
        }
        shows = [Show(id: "show-wand", name: "The Wand", seasonCount: 2, episodeCount: 30)]
        showEpisodes["show-wand"] = (1...15).map { Self.wandID(season: 1, episode: $0) } + (1...15).map { Self.wandID(season: 2, episode: $0) }

        // Films: the 4K movie with chapters and bookmarks ("DON’T BLINK", Figma Controls).
        var dontBlink = MediaItem(
            id: Self.dontBlinkID, mrl: Self.fileMRL("Videos/Films/DON’T BLINK.mp4"), title: "DON’T BLINK", fileName: "DON’T BLINK.mp4",
            // Continue Watching bar: 18 px of the Figma card (S43).
            kind: .video, duration: .hms(1, 58, 20), progress: 0.029, year: 2003, videoSize: CGSize(width: 3840, height: 2160))
        dontBlink.lastPlayedDate = mockReferenceDate.addingTimeInterval(-14_400)
        addMedia(dontBlink, folder: "films")
        chapters[Self.dontBlinkID] = [
            Chapter(index: 0, name: "Winter", time: .hms(0, 2, 15)),
            Chapter(index: 1, name: "Spring", time: .hms(0, 29, 45)),
            Chapter(index: 2, name: "Summer", time: .hms(0, 51, 30)),
            Chapter(index: 3, name: "Fall", time: .hms(1, 13, 50)),
            Chapter(index: 4, name: "Winter (5 Years Later)", time: .hms(1, 44, 10)),
        ]
        bookmarks[Self.dontBlinkID] = [
            Bookmark(id: "bm-1", mediaID: Self.dontBlinkID, name: "DON’T BLINK 1", time: .hms(0, 0, 42, milliseconds: 23)),
            Bookmark(id: "bm-2", mediaID: Self.dontBlinkID, name: "DON’T BLINK 2", time: .hms(0, 0, 44, milliseconds: 125)),
        ]
        for (index, film) in ["Northern Lights.mkv", "The Last Lighthouse.mp4", "Paper Planes.mp4", "Quiet Harbor.mkv"].enumerated() {
            let seconds = 85 * 60 + Int(stableHash(film) % 2_400)
            addMedia(MediaItem(id: "ml:film-\(index + 2)", mrl: Self.fileMRL("Videos/Films/" + film),
                               title: (film as NSString).deletingPathExtension, fileName: film, kind: .video,
                               duration: .seconds(Double(seconds)), videoSize: CGSize(width: 1920, height: 1080)), folder: "films")
        }

        // Anime: three shows of 24 episodes (pads the library to 110 media).
        for (showIndex, show) in [("kaze", "Kaze no Tabi"), ("courier", "Starlight Courier"), ("paper-moon", "Paper Moon Club")].enumerated() {
            addFolder("anime-" + show.0, show.1, parent: "anime", kind: .video, path: "Videos/Anime/" + show.1)
            let showID = "show-" + show.0
            var ids: [String] = []
            for episode in 1...24 {
                let name = show.1.replacingOccurrences(of: " ", with: "_") + "_E\(String(format: "%02d", episode)).mkv"
                let id = "ml:\(show.0)-e\(String(format: "%02d", episode))"
                var item = MediaItem(id: id, mrl: Self.fileMRL("Videos/Anime/\(show.1)/" + name), title: name, fileName: name,
                                     kind: .video, duration: .seconds(Double(23 * 60 + Int(stableHash(name) % 120))),
                                     episode: EpisodeInfo(showID: showID, showName: show.1, season: 1, episode: episode),
                                     videoSize: CGSize(width: 1920, height: 1080))
                // Watched a week or more ago: like the media library, a play count comes with a last-played date.
                if showIndex == 0 && episode <= 6 {
                    item.playCount = 1
                    item.lastPlayedDate = mockReferenceDate.addingTimeInterval(TimeInterval(-86_400 * (14 - episode)))
                }
                addMedia(item, folder: "anime-" + show.0)
                ids.append(id)
            }
            shows.append(Show(id: showID, name: show.1, seasonCount: 1, episodeCount: 24))
            showEpisodes[showID] = ids
        }

        // Music: "Songs" ▸ "My Songs" by juxtopposed (Figma "Player - Music").
        addFolder(Self.mySongsFolder, "My Songs", parent: nil, kind: .audio, path: "Music/My Songs")
        let songs: [(String, String, MediaTime)] = [
            (Self.untangleID, "untangle", .hms(0, 1, 40)),
            (Self.moonlightID, "moonlight", .hms(0, 2, 5)),
            (Self.blackBirdID, "black bird", .hms(0, 1, 52)),
        ]
        for (index, song) in songs.enumerated() {
            var item = MediaItem(id: song.0, mrl: Self.fileMRL("Music/My Songs/\(song.1).mp3"), title: song.1, fileName: "\(song.1).mp3",
                                 kind: .audio, duration: song.2, artist: "juxtopposed", album: "Night Drafts", albumArtist: "juxtopposed",
                                 genre: "Lo-fi", trackNumber: index + 1, discNumber: 1, year: 2026)
            item.playCount = 3 - index
            item.lastPlayedDate = mockReferenceDate.addingTimeInterval(TimeInterval(-1_800 * (index + 1)))
            addMedia(item, folder: Self.mySongsFolder)
        }
        albums = [Album(id: "album-night-drafts", title: "Night Drafts", artist: "juxtopposed", year: 2026, trackCount: 3, duration: .hms(0, 5, 37))]
        albumTracks["album-night-drafts"] = songs.map(\.0)
        artists = [Artist(id: "artist-juxtopposed", name: "juxtopposed", albumCount: 1, trackCount: 3)]
        genres = [Genre(id: "genre-lofi", name: "Lo-fi", trackCount: 3)]
        genreTracks["genre-lofi"] = songs.map(\.0)

        // Playlists (Figma "Playlists": Cool Songs, Anime to Watch).
        playlists = [
            MockPlaylist(playlist: Playlist(id: "pl-cool-songs", name: "Cool Songs"), mediaIDs: songs.map(\.0), addedOrder: 0),
            MockPlaylist(playlist: Playlist(id: "pl-anime-to-watch", name: "Anime to Watch"),
                         mediaIDs: (1...4).map { "ml:courier-e0\($0)" } + (1...3).map { "ml:paper-moon-e0\($0)" }, addedOrder: 1),
        ]
        for index in playlists.indices { refreshPlaylistStats(index) }

        // Network streams (Figma "Network": Podcasts, Radio — the seeded defaults). Collections are saved
        // with their items: an m3u is expanded into its channels when it is saved (here "TV Channels").
        seedDefaultStreams()
        streams.append(MockStream(stream: Self.expandedStream(id: "stream-tv", name: "TV Channels", channels: 12), addedOrder: 2))

        for id in folders.keys { refreshFolderCount(id) }
    }

    mutating func refreshFolderCount(_ id: String) {
        guard let folder = folders[id] else { return }
        folders[id]?.folder.itemCount = folder.subfolderIDs.count + folder.mediaIDs.count
    }

    mutating func refreshPlaylistStats(_ index: Int) {
        let ids = playlists[index].mediaIDs
        playlists[index].playlist.itemCount = ids.count
        playlists[index].playlist.duration = ids.compactMap { media[$0]?.duration }.reduce(.zero, +)
    }

    /// An m3u collection as the real backend saves it: one URL per channel, titled from #EXTINF.
    static func expandedStream(id: String, name: String, channels: Int) -> NetworkStream {
        NetworkStream(id: id, name: name, urls: (1...max(1, channels)).map { URL(string: "https://iptv.example.com/channel-\($0).m3u8")! }, itemCount: channels)
    }

    mutating func makeID(_ prefix: String) -> String {
        nextID += 1
        return "\(prefix)-\(nextID)"
    }

    // MARK: Queries

    /// Breadcrumb from the category root (as in the Figma panels).
    func breadcrumb(for location: LibraryLocation) -> [LibraryCrumb] {
        switch location {
        case .homeSection(let kind): return [LibraryCrumb(title: "Home", location: .home), LibraryCrumb(title: kind.title, location: location)]
        case .home: return [LibraryCrumb(title: "Home", location: .home)]
        case .videos: return [LibraryCrumb(title: "Videos", location: .videos)]
        case .music: return [LibraryCrumb(title: "Music", location: .music)]
        case .songs: return [LibraryCrumb(title: "Music", location: .music), LibraryCrumb(title: "Songs", location: .songs)]
        case .albums: return [LibraryCrumb(title: "Music", location: .music), LibraryCrumb(title: "Albums", location: .albums)]
        case .artists: return [LibraryCrumb(title: "Music", location: .music), LibraryCrumb(title: "Artists", location: .artists)]
        case .genres: return [LibraryCrumb(title: "Music", location: .music), LibraryCrumb(title: "Genres", location: .genres)]
        case .network: return [LibraryCrumb(title: "Network", location: .network)]
        case .playlists: return [LibraryCrumb(title: "Playlists", location: .playlists)]
        case .recent: return [LibraryCrumb(title: "Recent", location: .recent)]
        case .album(let id):
            return breadcrumb(for: .albums) + [LibraryCrumb(title: albums.first { $0.id == id }?.title ?? "Album", location: location)]
        case .artist(let id):
            return breadcrumb(for: .artists) + [LibraryCrumb(title: artists.first { $0.id == id }?.name ?? "Artist", location: location)]
        case .genre(let id):
            return breadcrumb(for: .genres) + [LibraryCrumb(title: genres.first { $0.id == id }?.name ?? "Genre", location: location)]
        case .playlist(let id):
            return breadcrumb(for: .playlists) + [LibraryCrumb(title: playlists.first { $0.playlist.id == id }?.playlist.name ?? "Playlist", location: location)]
        case .stream(let id):
            return breadcrumb(for: .network) + [LibraryCrumb(title: streams.first { $0.stream.id == id }?.stream.name ?? "Stream", location: location)]
        case .show(let id):
            return breadcrumb(for: .videos) + [LibraryCrumb(title: shows.first { $0.id == id }?.name ?? "Show", location: location)]
        case .folder(let id):
            var chain: [LibraryCrumb] = []
            var current: String? = id
            var isAudio = false
            while let folderID = current, let folder = folders[folderID] {
                chain.insert(LibraryCrumb(title: folder.folder.name, location: .folder(folderID)), at: 0)
                if folder.parentID == nil { isAudio = folder.folder.contentKind == .audio }
                current = folder.parentID
            }
            return (isAudio ? breadcrumb(for: .songs) : breadcrumb(for: .videos)) + chain
        }
    }

    /// Unsorted entries at a location, plus its "+" row.
    func entries(at location: LibraryLocation) -> (entries: [LibraryEntry], add: LibraryAddAction?) {
        switch location {
        case .homeSection(let kind): return (homeSections(capped: false).first { $0.kind == kind }?.entries ?? [], nil)
        case .home:
            return ([], nil)
        case .videos:
            return (videoRoots.compactMap { folders[$0].map { .folder($0.folder) } }, .add)
        case .music:
            return ([
                .link(LibraryLink(title: "Songs", destination: .songs, iconName: "music")),
                .link(LibraryLink(title: "Albums", destination: .albums, iconName: "album")),
                .link(LibraryLink(title: "Artists", destination: .artists, iconName: "artist")),
                .link(LibraryLink(title: "Genres", destination: .genres, iconName: "genre")),
            ], .add)
        case .songs:
            return (audioRoots.compactMap { folders[$0].map { .folder($0.folder) } }, .add)
        case .albums: return (albums.map { .album($0) }, nil)
        case .artists: return (artists.map { .artist($0) }, nil)
        case .genres: return (genres.map { .genre($0) }, nil)
        case .network:
            return (streams.sorted { $0.addedOrder < $1.addedOrder }.map { .stream($0.stream) }, .addNetworkStream)
        case .playlists:
            return (playlists.sorted { $0.addedOrder < $1.addedOrder }.map { .playlist($0.playlist) }, .createPlaylist)
        case .recent:
            let played = mediaOrder.compactMap { media[$0] }.filter { $0.lastPlayedDate != nil }
            return (played.map { .media($0) }, nil)
        case .folder(let id):
            guard let folder = folders[id] else { return ([], nil) }
            let subfolders = folder.subfolderIDs.compactMap { folders[$0].map { LibraryEntry.folder($0.folder) } }
            let items = folder.mediaIDs.compactMap { media[$0].map { LibraryEntry.media($0) } }
            if folder.showsAddRow { return (subfolders + items, .add) }
            // Media-only folders show the "+ Add" row only at music roots (Figma "My Songs").
            return (subfolders + items, folder.folder.contentKind == .audio ? .add : nil)
        case .album(let id): return ((albumTracks[id] ?? []).compactMap { media[$0].map { .media($0) } }, nil)
        case .artist(let name):
            let tracks = mediaOrder.compactMap { media[$0] }.filter { "artist-" + ($0.artist ?? "") == name }
            return (tracks.map { .media($0) }, nil)
        case .genre(let id): return ((genreTracks[id] ?? []).compactMap { media[$0].map { .media($0) } }, nil)
        case .playlist(let id):
            let ids = playlists.first { $0.playlist.id == id }?.mediaIDs ?? []
            let revision = PlaylistOccurrence.revision(for: ids)
            return (ids.enumerated().compactMap { position, mediaID in
                guard var item = media[mediaID] else { return nil }
                item.playlistOccurrence = PlaylistOccurrence(playlistID: id, position: position, revision: revision)
                return .media(item)
            }, nil)
        case .show(let id): return ((showEpisodes[id] ?? []).compactMap { media[$0].map { .media($0) } }, nil)
        case .stream(let id):
            guard let stream = streams.first(where: { $0.stream.id == id })?.stream else { return ([], nil) }
            return (stream.urls.enumerated().map { index, url in
                var item = MediaItem(url: url)
                if url.host == "iptv.example.com" { item.title = "Channel \(index + 1)" }
                item.kind = .stream
                return .media(item)
            }, nil)
        }
    }

    /// Entries sorted and filtered as the query asks.
    func sortedEntries(at location: LibraryLocation, sort: LibrarySort, search: String) -> (entries: [LibraryEntry], add: LibraryAddAction?) {
        var (list, add) = entries(at: location)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            // At category roots, search covers every media of the category (like the ML search);
            // inside a folder it filters the folder.
            list = list.filter { $0.title.lowercased().contains(query) }
            if location == .home || location == .videos || location == .music || location == .songs {
                // Home searches the whole library (folders, playlists, then media of every kind), as the
                // VLC backend does; category roots add every media of their kind.
                let kind: MediaKind? = location == .home ? nil : (location.category == .music ? .audio : .video)
                if location == .home {
                    list += folders.values.map(\.folder).filter { $0.name.lowercased().contains(query) }
                        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { LibraryEntry.folder($0) }
                    list += playlists.filter { $0.playlist.name.lowercased().contains(query) }.map { LibraryEntry.playlist($0.playlist) }
                }
                let deep = mediaOrder.compactMap { media[$0] }.filter { (kind == nil || $0.kind == kind) && $0.listTitle.lowercased().contains(query) }
                let known = Set(list.map(\.id))
                list += deep.map { LibraryEntry.media($0) }.filter { !known.contains($0.id) }
            }
        }
        if case .homeSection = location { return (list, add) }
        // A playlist's dates are its own order (as MXRLibraryServices.m): oldest first is the order the
        // user built, newest first reverses it. Library index dates say nothing about the playlist.
        if case .playlist = location, sort == .oldestFirst || sort == .newestFirst {
            return (sort == .oldestFirst ? list : list.reversed(), add)
        }
        return (Self.sort(list, by: sort, order: mediaOrder), add)
    }

    static func sort(_ entries: [LibraryEntry], by sort: LibrarySort, order: [String]) -> [LibraryEntry] {
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        func rank(_ entry: LibraryEntry) -> Int {
            if let media = entry.media { return position[media.id] ?? Int.max }
            return -1
        }
        // Containers keep their scripted order and come before media.
        let containers = entries.filter { $0.media == nil }
        var items = entries.compactMap(\.media)
        func title(_ m: MediaItem) -> String { m.listTitle.lowercased() }
        switch sort {
        case .unwatchedFirst:
            items.sort { ($0.isWatched ? 1 : 0, title($0)) < ($1.isWatched ? 1 : 0, title($1)) }
        case .watchedFirst:
            items.sort { ($0.isWatched ? 0 : 1, title($0)) < ($1.isWatched ? 0 : 1, title($1)) }
        case .newestFirst:
            items.sort { ($0.lastPlayedDate ?? $0.addedDate ?? .distantPast) > ($1.lastPlayedDate ?? $1.addedDate ?? .distantPast) }
        case .oldestFirst:
            items.sort { rank(.media($0)) < rank(.media($1)) }
        case .titleAscending: items.sort { title($0) < title($1) }
        case .titleDescending: items.sort { title($0) > title($1) }
        case .artistAscending: items.sort { ($0.artist ?? "", title($0)) < ($1.artist ?? "", title($1)) }
        case .artistDescending: items.sort { ($0.artist ?? "", title($0)) > ($1.artist ?? "", title($1)) }
        case .albumAscending: items.sort { ($0.album ?? "", $0.trackNumber ?? 0) < ($1.album ?? "", $1.trackNumber ?? 0) }
        case .albumDescending: items.sort { ($0.album ?? "", $0.trackNumber ?? 0) > ($1.album ?? "", $1.trackNumber ?? 0) }
        case .trackNumberAscending: items.sort { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
        case .trackNumberDescending: items.sort { ($0.trackNumber ?? 0) > ($1.trackNumber ?? 0) }
        case .uriAscending: items.sort { $0.mrl < $1.mrl }
        case .uriDescending: items.sort { $0.mrl > $1.mrl }
        case .discNumberAscending: items.sort { ($0.discNumber ?? 0, $0.trackNumber ?? 0) < ($1.discNumber ?? 0, $1.trackNumber ?? 0) }
        case .discNumberDescending: items.sort { ($0.discNumber ?? 0, $0.trackNumber ?? 0) > ($1.discNumber ?? 0, $1.trackNumber ?? 0) }
        }
        return containers + items.map { .media($0) }
    }

    /// Home sections by the same rules as the VLC backend (MXRLibraryServices.m `homeSections`):
    /// non-empty sections only, each with the destination its "›" opens. Home (`capped`) holds at most
    /// ``LibraryHomeSectionKind/homeLimit`` entries per section; a section's own page holds all of them.
    func homeSections(capped: Bool = true) -> [LibraryHomeSection] {
        // History: media that were played, most recent first.
        let history = mediaOrder.compactMap { media[$0] }.filter { $0.lastPlayedDate != nil }
            .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
        var sections: [LibraryHomeSection] = []
        let continuing = history.filter { $0.kind == .video && $0.isInProgress }
        if !continuing.isEmpty { sections.append(LibraryHomeSection(kind: .continueWatching, entries: continuing.map { .media($0) }, destination: .homeSection(.continueWatching))) }
        let audio = history.filter { $0.kind == .audio }
        if !audio.isEmpty { sections.append(LibraryHomeSection(kind: .listenAgain, entries: audio.map { .media($0) }, destination: .homeSection(.listenAgain))) }
        // Folders and artists ranked by how often their media were played (stable: most recent first).
        func ranked(_ keys: [String]) -> [String] {
            var counts: [String: Int] = [:], order: [String] = []
            for key in keys { if counts[key] == nil { order.append(key) }; counts[key, default: 0] += 1 }
            return order.enumerated().sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }.map(\.element)
        }
        let folderEntries = (figmaHomeFolderIDs ?? ranked(history.compactMap { $0.folder?.id })).compactMap { folders[$0].map { LibraryEntry.folder($0.folder) } }
        if !folderEntries.isEmpty { sections.append(LibraryHomeSection(kind: .frequentFolders, entries: folderEntries, destination: .homeSection(.frequentFolders))) }
        let played = Set(history.map(\.id))
        let playlistEntries = playlists.map { ($0, $0.mediaIDs.filter(played.contains).count) }.filter { $0.1 > 0 }
            .enumerated().sorted { ($0.element.1, -$0.offset) > ($1.element.1, -$1.offset) }.map { LibraryEntry.playlist($0.element.0.playlist) }
        if !playlistEntries.isEmpty { sections.append(LibraryHomeSection(kind: .frequentPlaylists, entries: Array(playlistEntries), destination: .homeSection(.frequentPlaylists))) }
        let artistEntries = ranked(history.filter { $0.kind == .audio }.compactMap { $0.artist })
            .compactMap { name in artists.first { $0.name == name }.map { LibraryEntry.artist($0) } }
        if !artistEntries.isEmpty { sections.append(LibraryHomeSection(kind: .frequentArtists, entries: artistEntries, destination: .homeSection(.frequentArtists))) }
        let latest = streams.filter { !$0.seeded }.sorted { $0.addedOrder > $1.addedOrder }.map { LibraryEntry.stream($0.stream) }
        if !latest.isEmpty { sections.append(LibraryHomeSection(kind: .latestStreams, entries: Array(latest), destination: .homeSection(.latestStreams))) }
        return capped ? sections.map { LibraryHomeSection(kind: $0.kind, entries: Array($0.entries.prefix($0.kind.homeLimit)), destination: $0.destination) } : sections
    }

    /// All media under a location (folders recursively), for "play folder".
    func allMedia(at location: LibraryLocation) -> [MediaItem] {
        if case .folder(let id) = location, let folder = folders[id] {
            return folder.mediaIDs.compactMap { media[$0] } + folder.subfolderIDs.flatMap { allMedia(at: .folder($0)) }
        }
        return entries(at: location).entries.compactMap(\.media)
    }

    /// Updates a media everywhere it is referenced.
    mutating func update(_ id: String, _ change: (inout MediaItem) -> Void) {
        guard var item = media[id] else { return }
        change(&item)
        media[id] = item
    }
}

/// Deterministic subtitle cues for the timeline: a line every few seconds over `length`.
func mockSubtitleCues(seed: String, length: MediaTime) -> [SubtitleCue] {
    var generator = SeededGenerator(seed: stableHash(seed))
    var cues: [SubtitleCue] = []
    var start = MediaTime.seconds(3)
    var index = 1
    while start < length {
        let duration = MediaTime.milliseconds(Int64(900 + Int(generator.next() % 2_600)))
        let end = min(start + duration, length)
        cues.append(SubtitleCue(start: start, end: end, text: "Line \(index)"))
        index += 1
        start = end + .milliseconds(Int64(300 + Int(generator.next() % 4_200)))
    }
    return cues
}
