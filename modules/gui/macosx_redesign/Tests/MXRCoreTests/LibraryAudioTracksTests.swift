import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// Edit / Add Audio Tracks (S29 file, S30 folder, S31 playlist; D039): the chosen audio files are
/// attached in the media library to the media they belong to, and the playing one also gets the
/// track right away. The engine half (soundtracks loaded as selected slaves) is held by
/// Tests/NativeLibrarySoundtrackRuntime.m.
@MainActor
final class LibraryAudioTracksTests: XCTestCase {
    private func episodes(_ app: AppModel) async throws -> [MediaItem] {
        await app.library.allMedia(at: .folder(MockMediaID.theWandS01Folder))
    }
    private func settle() async { for _ in 0..<50 { await Task.yield() } }
    private func audio(_ name: String) -> URL { URL(fileURLWithPath: "/Users/Shared/Media/Dubs/" + name) }

    func testFolderAudioFilesGoToTheEpisodesTheyName() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = mock.makeAppModel(clockTicks: false)
        let library = try XCTUnwrap(app.backends.library as? MockLibrary)
        let media = try await episodes(app)
        let playing = try XCTUnwrap(app.player.media)
        let playingCode = try XCTUnwrap(SubtitleMatcher.episodeCode(in: playing.listTitle))
        let files = [audio("The Wand \(playingCode) English.m4a"), audio("The_Wand_S01E02_English.mp3"),
                     audio("Notes.txt"), audio("Unrelated.flac")]

        app.presentAddAudioTracks(media: media)
        XCTAssertEqual(app.interface.fileRequest, .addAudioFile, "the Add Audio File panel opens")
        app.complete(.addAudioFile, urls: files)
        await settle()

        let second = try XCTUnwrap(media.first { $0.episode?.episode == 2 })
        XCTAssertEqual(library.attachedAudioTracks[second.id], [files[1]], "E02 takes the file with its episode code")
        XCTAssertEqual(library.attachedAudioTracks[playing.id], [files[0]], "the playing episode takes its file")
        XCTAssertEqual(library.attachedAudioTracks.count, 2, "a non-audio file and a file naming no episode are left out")
        XCTAssertEqual(app.tracks.audioTracks.filter(\.isExternal).map(\.sourceURL), [files[0]],
                       "only the playing episode's file joins the running input")
        XCTAssertTrue(app.library.audioTrackTargets.isEmpty)
    }

    func testOneFileTakesEveryChosenAudioFile() async throws {
        let mock = MockBackend(scenario: .idle)
        let app = mock.makeAppModel(clockTicks: false)
        let library = try XCTUnwrap(app.backends.library as? MockLibrary)
        let all = try await episodes(app)
        let file = try XCTUnwrap(all.first)
        let files = [audio("Commentary.m4a"), audio("Dub.aac")]
        app.presentAddAudioTracks(media: [file])
        app.complete(.addAudioFile, urls: files)
        await settle()
        XCTAssertEqual(library.attachedAudioTracks[file.id], files)
        XCTAssertTrue(app.tracks.audioTracks.filter(\.isExternal).isEmpty, "nothing plays, so no live track is added")
    }

    /// Cancelling the panel forgets the library targets: the player's own Add Audio File then adds
    /// to the playing media only and never to the folder chosen earlier.
    func testCancelledPanelDoesNotLeakIntoThePlayersAddAudioFile() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = mock.makeAppModel(clockTicks: false)
        let library = try XCTUnwrap(app.backends.library as? MockLibrary)
        app.presentAddAudioTracks(media: try await episodes(app))
        app.complete(.addAudioFile, urls: [])
        app.interface.request(.addAudioFile)
        let file = audio("The_Wand_S01E02_English.mp3")
        app.complete(.addAudioFile, urls: [file])
        await settle()
        XCTAssertTrue(library.attachedAudioTracks.isEmpty, "the cancelled folder targets were dropped")
        XCTAssertEqual(app.tracks.audioTracks.filter(\.isExternal).map(\.sourceURL), [file])
    }

    func testNothingMatchedSaysWhy() async throws {
        let mock = MockBackend(scenario: .idle)
        let app = mock.makeAppModel(clockTicks: false)
        app.presentAddAudioTracks(media: try await episodes(app))
        app.complete(.addAudioFile, urls: [audio("Unrelated.flac")])
        let error = try XCTUnwrap(app.dialogs.current)
        XCTAssertEqual(error.title, "No Audio Tracks Were Added")
        XCTAssertTrue(error.text.contains("episode number"), error.text)
    }

    func testNoticeNamesTheFileOrCountsThem() {
        let a = MediaItem(url: URL(fileURLWithPath: "/m/The_Wand_S01E01.mp4")), b = MediaItem(url: URL(fileURLWithPath: "/m/The_Wand_S01E02.mp4"))
        XCTAssertEqual(LibraryAudioTracks.notice([.init(media: a, url: audio("x.m4a"))]), "Audio track added to \(a.listTitle).")
        XCTAssertEqual(LibraryAudioTracks.notice([.init(media: a, url: audio("x.m4a")), .init(media: b, url: audio("y.m4a"))]),
                       "Audio tracks added to 2 files.")
    }
}
