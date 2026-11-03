import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// R04: Add File takes video and audio only, keeps the good files of a selection when some are left
/// out (one message names those), and its files can be removed from the library again.
@MainActor
final class LibraryImportRemovalTests: XCTestCase {
    private func settle(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { await Task.yield() }
    }

    func testOnlyVideoAndAudioFilesAreLibraryMedia() {
        for name in ["Clip.mkv", "Clip.MP4", "Song.mp3", "Song.FLAC", "Track.wv", "Tune.mid", "Disc.iso"] {
            XCTAssertTrue(MediaItem.isLibraryMedia(URL(fileURLWithPath: "/tmp/" + name)), name)
        }
        for name in ["notes.txt", "photo.jpg", "Clip.srt", "list.m3u", "archive.zip", "noextension"] {
            XCTAssertFalse(MediaItem.isLibraryMedia(URL(fileURLWithPath: "/tmp/" + name)), name)
        }
        XCTAssertFalse(MediaItem.isLibraryMedia(URL(string: "https://example.com/stream.mp4")!), "streams are not Add File media")
        XCTAssertEqual(MediaItem.kind(of: URL(fileURLWithPath: "/tmp/Track.wv")), .audio, "VLC's audio-only extensions list under Songs")
        XCTAssertEqual(MediaItem.kind(of: URL(fileURLWithPath: "/tmp/Clip.ogv")), .video)
    }

    func testAddFileImportsTheMediaAndNamesTheFilesLeftOutInOneMessage() async throws {
        let app = MockBackend(scenario: .idle).makeAppModel(clockTicks: false)
        let clip = URL(fileURLWithPath: "/tmp/R04/Clip.mp4")
        let notes = URL(fileURLWithPath: "/tmp/R04/notes.txt"), photo = URL(fileURLWithPath: "/tmp/R04/photo.jpg")
        do {
            try await app.library.importFiles(urls: [notes, clip, photo])
            XCTFail("the files left out are reported")
        } catch let error as LibraryImportError {
            XCTAssertEqual(error.rejected, [notes, photo])
            XCTAssertEqual(error.imported.map(\.mrl), [clip.absoluteString])
            XCTAssertEqual(error.localizedDescription,
                           "2 files could not be added to the library: “notes.txt”, “photo.jpg”. Only video and audio files that can be read are added. The other file was added.")
        }
        await settle { !app.library.selection.isEmpty }
        XCTAssertEqual(app.library.location, .videos, "the good file is still shown where it was added")
        XCTAssertEqual(app.library.selection, [LibraryEntry.media(MediaItem(url: clip)).id])
        XCTAssertFalse(app.library.entries.contains { $0.media?.mrl == notes.absoluteString }, "text never lists under Videos")
    }

    func testAddFileOfOnlyNonMediaChangesNothing() async throws {
        let app = MockBackend(scenario: .idle).makeAppModel(clockTicks: false)
        app.library.navigate(to: .playlists)
        let notes = URL(fileURLWithPath: "/tmp/R04/notes.txt")
        do {
            try await app.library.importFiles(urls: [notes])
            XCTFail("a text file is refused")
        } catch let error as LibraryImportError {
            XCTAssertEqual(error.localizedDescription, "“notes.txt” could not be added to the library. Only video and audio files that can be read are added.")
        }
        XCTAssertEqual(app.library.location, .playlists)
    }

    func testRemoveFromLibraryTakesImportedFilesOut() async throws {
        let mock = MockBackend(scenario: .idle)
        let app = mock.makeAppModel(clockTicks: false)
        let first = URL(fileURLWithPath: "/tmp/R04/First.mp4"), second = URL(fileURLWithPath: "/tmp/R04/Second.mp4")
        try await app.library.importFiles(urls: [first, second])
        await settle { app.library.mediaEntries.filter(\.isImported).count == 2 }
        let imported = app.library.mediaEntries.filter(\.isImported)
        XCTAssertEqual(Set(imported.map(\.mrl)), [first.absoluteString, second.absoluteString], "imports carry the flag the menu reads")

        try await app.library.removeImported(imported)
        await settle { !app.library.mediaEntries.contains(where: \.isImported) }
        XCTAssertFalse(app.library.mediaEntries.contains { $0.mrl == first.absoluteString || $0.mrl == second.absoluteString })
        XCTAssertTrue(app.library.selection.isEmpty, "removed rows leave the selection")
    }

    func testRemoveFromLibraryIgnoresMediaThatWasNotImported() async throws {
        let mock = MockBackend(scenario: .idle)
        let app = mock.makeAppModel(clockTicks: false)
        let scanned = await app.library.allMedia(at: .folder(MockMediaID.theWandS01Folder))
        let episode = try XCTUnwrap(scanned.first)
        XCTAssertFalse(episode.isImported)
        try await app.library.removeImported([episode])
        let after = await app.library.allMedia(at: .folder(MockMediaID.theWandS01Folder))
        XCTAssertEqual(after.map(\.id), scanned.map(\.id), "folder media leave only with their folder")
    }

    func testPinnedImportKeepsItsImportedFlag() throws {
        var item = MediaItem(url: URL(fileURLWithPath: "/tmp/R04/Clip.mp4"))
        item.importedFile = true
        let decoded = try JSONDecoder().decode(MediaItem.self, from: JSONEncoder().encode(item))
        XCTAssertTrue(decoded.isImported, "pins and recents decode through MediaItem's tolerant decoder (R05)")
    }
}
