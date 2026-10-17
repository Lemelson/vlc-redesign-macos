import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// The library contract both backends implement (L04): the mock is held to the same rules as the VLC
/// bridge (`module/bridge/MXRLibraryServices.m`), so gallery renders reflect what the app shows.
///
/// - Category roots: Videos / Songs list entry-point folders with "+ Add"; Music lists the four links
///   with "+ Add"; Network lists saved collections with "+ Add Network Stream"; Playlists lists playlists
///   with "+ Create playlist".
/// - Folders: subfolders first, then media; "+ Add" where folders can grow (folders of folders, music).
/// - Breadcrumbs start at the category root, every crumb navigates, the last one is the location.
/// - Home: only non-empty sections, each with the destination its "›" opens, in design order.
/// - Progress: a partial position is a progress in 0<p<1; a watched item has a play count and no
///   position (VLC resets it to -1, the bridge omits it) and draws a full line.
@MainActor
final class MockLibraryContractTests: XCTestCase {
    private let library = MockBackend(scenario: .idle).library

    private func page(_ location: LibraryLocation, search: String = "") async throws -> LibraryPage {
        try await library.page(at: location, query: LibraryQuery(sort: .titleAscending, searchText: search, limit: 1_000))
    }

    func testCategoryRootsOfferTheirAddRows() async throws {
        let videos = try await page(.videos)
        XCTAssertEqual(videos.addAction, .add)
        XCTAssertTrue(videos.entries.allSatisfy { if case .folder(let f) = $0 { return f.isEntryPoint }; return false })

        let music = try await page(.music)
        XCTAssertEqual(music.addAction, .add)
        XCTAssertEqual(music.entries.compactMap(\.destination), [.songs, .albums, .artists, .genres])

        let songs = try await page(.songs)
        XCTAssertEqual(songs.addAction, .add)
        XCTAssertFalse(songs.entries.isEmpty)
        XCTAssertTrue(songs.entries.allSatisfy { if case .folder(let f) = $0 { return f.contentKind == .audio }; return false })

        let network = try await page(.network)
        XCTAssertEqual(network.addAction, .addNetworkStream)
        let playlists = try await page(.playlists)
        XCTAssertEqual(playlists.addAction, .createPlaylist)
        let recent = try await page(.recent)
        XCTAssertNil(recent.addAction)
        XCTAssertTrue(recent.entries.allSatisfy { $0.media != nil })
    }

    func testFoldersListSubfoldersBeforeMediaAndCountBoth() async throws {
        let wand = try await page(.folder("wand"))
        XCTAssertEqual(wand.entries.map(\.title), ["S01", "S02"])
        XCTAssertEqual(wand.addAction, .add, "a folder of folders can grow")
        let season = try await page(.folder(MockMediaID.theWandS01Folder))
        XCTAssertNil(season.addAction, "a video folder of files has no + row (Figma 848:1995)")
        XCTAssertEqual(season.totalCount, 15)
        let firstMedia = try XCTUnwrap(season.entries.firstIndex { $0.media != nil })
        XCTAssertTrue(season.entries[..<firstMedia].allSatisfy { $0.destination != nil })
        let mySongs = try await page(.folder(MockMediaID.mySongsFolder))
        XCTAssertEqual(mySongs.addAction, .add, "music folders show + Add (key frame 12m18.4s)")
    }

    func testBreadcrumbsStartAtTheCategoryAndNavigate() async throws {
        for location: LibraryLocation in [.folder(MockMediaID.theWandS01Folder), .folder(MockMediaID.mySongsFolder), .albums, .playlists, .network] {
            let crumbs = await library.breadcrumb(for: location)
            XCTAssertEqual(crumbs.last?.location, location)
            XCTAssertEqual(crumbs.first?.location, crumbs.first?.location.category.location, "the first crumb is a category root")
            for crumb in crumbs { _ = try await page(crumb.location) }
        }
        let season = await library.breadcrumb(for: .folder(MockMediaID.theWandS01Folder))
        XCTAssertEqual(season.map(\.title), ["Videos", "Shows", "The Wand", "S01"])
        let songs = await library.breadcrumb(for: .folder(MockMediaID.mySongsFolder))
        XCTAssertEqual(songs.map(\.title), ["Music", "Songs", "My Songs"])
    }

    func testHomeSectionsAreNonEmptyWithDestinationsInDesignOrder() async throws {
        let sections = try await library.homeSections()
        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.allSatisfy { !$0.entries.isEmpty && $0.destination != nil })
        let order = LibraryHomeSectionKind.allCases
        XCTAssertEqual(sections.map(\.kind), order.filter { kind in sections.contains { $0.kind == kind } })
        let continueWatching = try XCTUnwrap(sections.first { $0.kind == .continueWatching })
        XCTAssertTrue(continueWatching.entries.allSatisfy { $0.media?.kind == .video && $0.media?.isInProgress == true })
        let empty = MockBackend(scenario: .emptyLibrary).library
        let emptySections = try await empty.homeSections()
        XCTAssertEqual(emptySections, [])
    }

    func testProgressFollowsTheMediaLibrary() async throws {
        let season = try await page(.folder(MockMediaID.theWandS01Folder)).entries.compactMap(\.media)
        for media in season {
            if media.isWatched {
                XCTAssertNil(media.progress, "\(media.title): a completed play clears the position")
                XCTAssertEqual(media.displayProgress, 1)
            } else if let progress = media.progress {
                XCTAssertTrue(progress > 0 && progress < 1)
            }
        }
        let e05 = try XCTUnwrap(season.first { $0.episode?.episode == 5 })
        library.setWatched(true, mediaIDs: [e05.id])
        let watched = try XCTUnwrap(library.mediaItem(id: e05.id))
        XCTAssertNil(watched.progress)
        XCTAssertEqual(watched.displayProgress, 1)
    }

    func testMediaCarryTheirFolderAndMusicMetadata() async throws {
        let season = try await page(.folder(MockMediaID.theWandS01Folder)).entries.compactMap(\.media)
        XCTAssertTrue(season.allSatisfy { $0.folder?.id == MockMediaID.theWandS01Folder && $0.folder?.name == "S01" })
        let songs = try await page(.folder(MockMediaID.mySongsFolder)).entries.compactMap(\.media)
        let untangle = try XCTUnwrap(songs.first { $0.id == MockDatabase.untangleID })
        XCTAssertEqual(untangle.listTitle, "untangle - juxtopposed")
        XCTAssertNotNil(untangle.trackNumber)
    }

    func testHomeSearchCoversTheWholeLibrary() async throws {
        let results = try await page(.home, search: "cool")
        XCTAssertTrue(results.entries.contains { if case .playlist = $0 { return true }; return false })
        let media = try await page(.home, search: "untangle")
        XCTAssertEqual(media.entries.compactMap(\.media).map(\.title), ["untangle"])
        XCTAssertEqual(media.totalCount, media.entries.count)
    }

    func testSavedCollectionsBrowseAndAppearOnlyInNetwork() async throws {
        let network = try await page(.network)
        let tv = try XCTUnwrap(network.entries.first { $0.title == "TV Channels" })
        XCTAssertEqual(tv.destination, .stream("stream-tv"))
        let channels = try await page(.stream("stream-tv"))
        XCTAssertEqual(channels.totalCount, 12)
        let playlists = try await page(.playlists)
        XCTAssertFalse(playlists.entries.contains { $0.title == "TV Channels" })
    }
}
