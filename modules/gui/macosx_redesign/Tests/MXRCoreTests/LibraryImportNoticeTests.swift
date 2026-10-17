import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// A mixed Add File import (videos and songs) shows the videos and says where the songs went.
@MainActor
final class LibraryImportNoticeTests: XCTestCase {
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { await Task.yield() }
    }

    func testMixedImportShowsVideosAndOffersTheSongs() async throws {
        let mock = MockBackend(scenario: .idle)
        let app = mock.makeAppModel(clockTicks: false)
        app.library.navigate(to: .home)
        let video = URL(fileURLWithPath: "/Users/Shared/Media/Imported/Clip.mp4")
        let song = URL(fileURLWithPath: "/Users/Shared/Media/Imported/Song.flac")
        try await app.library.importFiles(urls: [video, song])
        await settle { !app.library.selection.isEmpty }

        XCTAssertEqual(app.library.location, .videos)
        XCTAssertEqual(app.library.selection, [LibraryEntry.media(MediaItem(url: video)).id], "only the videos are selected in Videos")
        let notice = try XCTUnwrap(app.library.importNotice, "the songs are not silently dropped")
        XCTAssertEqual(notice.shownAt, .videos)
        XCTAssertEqual(notice.message, "1 song was added to Music ▸ Songs.")

        app.library.showImportedSongs()
        await settle { app.library.selection.contains(LibraryEntry.media(MediaItem(url: song)).id) }
        XCTAssertEqual(app.library.location, .songs)
        XCTAssertEqual(app.library.selection, [LibraryEntry.media(MediaItem(url: song)).id], "Songs opens with the imported song selected")
        XCTAssertNil(app.library.importNotice)
    }

    func testNoticeBelongsToVideosAndSingleKindImportsHaveNone() async throws {
        let mock = MockBackend(scenario: .idle)
        let app = mock.makeAppModel(clockTicks: false)
        try await app.library.importFiles(urls: [URL(fileURLWithPath: "/tmp/A.mp4"), URL(fileURLWithPath: "/tmp/B.mp3"), URL(fileURLWithPath: "/tmp/C.mp3")])
        XCTAssertEqual(app.library.importNotice?.message, "2 songs were added to Music ▸ Songs.")
        app.library.navigate(to: .playlists)
        XCTAssertNil(app.library.importNotice, "leaving Videos drops the notice")

        try await app.library.importFiles(urls: [URL(fileURLWithPath: "/tmp/D.mp3")])
        XCTAssertEqual(app.library.location, .songs)
        XCTAssertNil(app.library.importNotice, "a songs-only import lands in Songs and needs no notice")
        try await app.library.importFiles(urls: [URL(fileURLWithPath: "/tmp/E.mp4")])
        XCTAssertNil(app.library.importNotice)
    }
}
