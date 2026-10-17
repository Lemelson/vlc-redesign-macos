import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// Final-wave library behaviour: Home caps (D044), playlist order under date sorts, import feedback.
@MainActor
final class LibraryHomeAndPlaylistOrderTests: XCTestCase {
    private func loaded(_ model: LibraryModel) async {
        for _ in 0..<1_000 where model.isLoading || !model.hasLoaded { await Task.yield() }
    }

    func testHomeRowsAreCappedAndShowAllListsEverything() async throws {
        let backend = MockBackend(scenario: .idle).library
        // More in-progress videos than a Home row holds.
        let urls = (0..<25).map { URL(fileURLWithPath: "/tmp/HomeCap\($0).mp4") }
        for url in urls { try await backend.importFiles(urls: [url]) }
        for (index, url) in urls.enumerated() {
            backend.db.media[url.absoluteString]?.progress = 0.5
            backend.db.media[url.absoluteString]?.lastPlayedDate = Date(timeIntervalSince1970: 1_000 + Double(index))
        }
        let home = try await backend.homeSections()
        let continuing = try XCTUnwrap(home.first { $0.kind == .continueWatching })
        XCTAssertEqual(continuing.entries.count, LibraryHomeSectionKind.continueWatching.homeLimit)
        let all = try await backend.page(at: .homeSection(.continueWatching), query: LibraryQuery(limit: 100))
        XCTAssertGreaterThan(all.totalCount, continuing.entries.count)
        XCTAssertEqual(all.entries.prefix(continuing.entries.count).map(\.id), continuing.entries.map(\.id))
    }

    func testCompactHomeKeepsEveryFigmaSection() async throws {
        // Figma 1106:5633: the compact panel lists folders, playlists and artists too (D044).
        let model = LibraryModel(backend: MockBackend(scenario: .idle).library)
        await loaded(model)
        XCTAssertTrue(model.homeSections.contains { $0.kind == .frequentFolders })
    }

    func testPlaylistDateSortsFollowThePlaylistOrder() async throws {
        let backend = MockBackend(scenario: .idle).library
        // "Bravo" is registered (indexed) after "Alpha", but the user put it first.
        _ = try await backend.createPlaylist(name: "Index order", mediaIDs: ["https://fixture.invalid/Alpha.mp4", "https://fixture.invalid/Bravo.mp4"], artworkURL: nil)
        let playlist = try await backend.createPlaylist(name: "Order", mediaIDs: ["https://fixture.invalid/Bravo.mp4", "https://fixture.invalid/Alpha.mp4"], artworkURL: nil)
        XCTAssertEqual(LibraryModel.defaultSorts[.playlists], .oldestFirst)
        let oldest = try await backend.page(at: .playlist(playlist.id), query: LibraryQuery(sort: .oldestFirst))
        XCTAssertEqual(oldest.entries.map(\.title), ["Bravo.mp4", "Alpha.mp4"])
        let newest = try await backend.page(at: .playlist(playlist.id), query: LibraryQuery(sort: .newestFirst))
        XCTAssertEqual(newest.entries.map(\.title), ["Alpha.mp4", "Bravo.mp4"])
    }

    func testImportShowsAndSelectsTheImportedFile() async throws {
        let model = LibraryModel(backend: MockBackend(scenario: .idle).library, initialLocation: .playlists)
        await loaded(model)
        let url = URL(fileURLWithPath: "/tmp/ImportFeedback.m4a")
        try await model.importFiles(urls: [url])
        XCTAssertEqual(model.location, .songs)
        await loaded(model)
        XCTAssertEqual(model.selectedMedia.map(\.mrl), [url.absoluteString])
    }

    func testFileKindUsesTheSystemType() {
        XCTAssertEqual(MediaItem.kind(of: URL(fileURLWithPath: "/tmp/a.mp3")), .audio)
        XCTAssertEqual(MediaItem.kind(of: URL(fileURLWithPath: "/tmp/a.caf")), .audio)
        XCTAssertEqual(MediaItem.kind(of: URL(fileURLWithPath: "/tmp/a.mkv")), .video)
        XCTAssertEqual(MediaItem.kind(of: URL(string: "https://example.com/live")!), .stream)
    }
}
