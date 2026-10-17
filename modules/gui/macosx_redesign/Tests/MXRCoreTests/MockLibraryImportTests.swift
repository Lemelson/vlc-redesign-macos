import XCTest
@testable import MXRCore
@testable import MXRMockBackend

@MainActor
final class MockLibraryImportTests: XCTestCase {
    func testExternalURLsBecomePlayablePlaylistItems() async throws {
        let mock = MockBackend(scenario: .emptyLibrary)
        let app = mock.makeAppModel(clockTicks: false)
        let fileURL = URL(fileURLWithPath: "/Users/Shared/Media/Imported clip #1.mp4")
        let streamURL = try XCTUnwrap(URL(string: "https://example.com/live.m3u8?token=fixture"))
        let playlist = try await app.library.createPlaylist(name: "Imported", media: [MediaItem(url: fileURL), MediaItem(url: streamURL)])

        XCTAssertEqual(playlist.itemCount, 2)
        XCTAssertEqual(mock.library.mediaCount, 2)
        let items = try await mock.library.allMedia(at: .playlist(playlist.id), sort: .oldestFirst)
        XCTAssertEqual(items.map(\.id), [fileURL.absoluteString, streamURL.absoluteString])
        XCTAssertEqual(items.map(\.mrl), [fileURL.absoluteString, streamURL.absoluteString])
        XCTAssertEqual(items.map(\.kind), [.video, .stream])
        XCTAssertEqual(items.first?.title, "Imported clip #1.mp4")
        let first = try XCTUnwrap(items.first)
        app.play(first, context: items)
        XCTAssertEqual(app.player.media?.mrl, fileURL.absoluteString)
        XCTAssertEqual(app.queue.items.map(\.media.mrl), [fileURL.absoluteString, streamURL.absoluteString])
    }

    func testAppendPreservesRegisteredMediaAndDuplicatePositions() async throws {
        let mock = MockBackend(scenario: .idle)
        let registered = try XCTUnwrap(mock.library.mediaItem(id: MockDatabase.untangleID))
        let originalCount = mock.library.mediaCount
        let playlist = try await mock.library.createPlaylist(name: "Mixed", mediaIDs: [registered.id], artworkURL: nil)
        let imported = URL(fileURLWithPath: "/Users/Shared/Media/New song.flac")
        try await mock.library.appendToPlaylist(id: playlist.id, mediaIDs: [imported.absoluteString, registered.id, imported.absoluteString])

        let page = try await mock.library.page(at: .playlist(playlist.id), query: LibraryQuery(sort: .oldestFirst))
        XCTAssertEqual(page.totalCount, 4)
        let registeredOccurrences = page.entries.compactMap(\.media).filter { $0.id == registered.id }
        XCTAssertEqual(registeredOccurrences.count, 2)
        XCTAssertEqual(registeredOccurrences.compactMap { $0.playlistOccurrence?.position }, [0, 2])
        for occurrence in registeredOccurrences {
            var expected = registered
            expected.playlistOccurrence = occurrence.playlistOccurrence
            XCTAssertEqual(occurrence, expected)
            XCTAssertEqual(occurrence.playlistOccurrence?.playlistID, playlist.id)
        }
        XCTAssertEqual(page.entries.compactMap(\.media).filter { $0.id == imported.absoluteString }.count, 2)
        XCTAssertEqual(mock.library.mediaItem(id: imported.absoluteString)?.kind, .audio)
        XCTAssertEqual(mock.library.mediaItem(id: registered.id), registered)
        XCTAssertEqual(mock.library.mediaCount, originalCount + 1)
        let playlists = try await mock.library.page(at: .playlists, query: LibraryQuery())
        let updated = playlists.entries.compactMap { entry -> Playlist? in
            if case .playlist(let value) = entry { return value }
            return nil
        }.first { $0.id == playlist.id }
        XCTAssertEqual(updated?.itemCount, 4)
        XCTAssertEqual(updated?.duration, registered.duration.map { $0 * 2 })
    }

    func testInvalidIDDoesNotPartiallyImportOrCreatePlaylist() async throws {
        let mock = MockBackend(scenario: .emptyLibrary)
        let fileID = URL(fileURLWithPath: "/Users/Shared/Media/New clip.mp4").absoluteString
        do {
            _ = try await mock.library.createPlaylist(name: "Invalid", mediaIDs: [fileID, "missing-media-id"], artworkURL: nil)
            XCTFail("An unknown identifier without an absolute URL must fail")
        } catch {
            XCTAssertEqual(error as? MockLibraryError, .notFound)
        }
        XCTAssertEqual(mock.library.mediaCount, 0)
        let page = try await mock.library.page(at: .playlists, query: LibraryQuery())
        XCTAssertTrue(page.entries.isEmpty)
    }

    func testLibraryLinkKeepsLegacyIdentityAndDecodesWithoutID() throws {
        let old = LibraryLink(title: "Shows", destination: .folder("shows"), iconName: "folder")
        XCTAssertEqual(LibraryEntry.link(old).id, "link:Shows")
        let encoded = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(LibraryLink.self, from: encoded)
        XCTAssertNil(decoded.id)
        XCTAssertEqual(decoded, old)
        let identified = LibraryLink(id: "tile-2", title: "Shows", destination: .folder("shows"), iconName: "folder")
        XCTAssertEqual(LibraryEntry.link(identified).id, "link:tile-2")
    }
}
