import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// Live run 2 (G-panels major): ⌘B on a file outside the media library showed "Bookmark added"
/// while nothing was stored. The OSD now reports the bookmark only once the library has stored it
/// (the bridge side, adding the file as external media, is in module/tests/library-contract.m).
@MainActor
final class BookmarkFeedbackTests: XCTestCase {
    func testKeyedBookmarkReportsSuccessOnlyAfterTheLibraryStoredIt() async throws {
        let app = AppModel.mock(.playingEpisode)
        let actionID = try XCTUnwrap(AppCommand.addBookmark.shortcutActionID)
        XCTAssertTrue(app.bookmarks.bookmarks.isEmpty)
        app.shortcuts.appActionHandler?(actionID, true)
        XCTAssertNotEqual(app.osd.message?.text, "Bookmark added", "nothing is stored yet")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(app.bookmarks.bookmarks.count, 1)
        XCTAssertEqual(app.osd.message?.text, "Bookmark added")
    }

    func testAddReportsFailureWithoutMedia() async throws {
        let app = AppModel.mock(.idle)
        var result: Bool?
        app.bookmarks.addAtCurrentTime { result = $0 }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(result, false)
        XCTAssertNotEqual(app.osd.message?.text, "Bookmark added")
    }
}

/// Live run 2 (polish 6): a new custom preset for a file opened directly (no show, no library
/// folder) was never selected: the file had no key to remember the preset under.
@MainActor
final class PresetForLooseFileTests: XCTestCase {
    func testAPresetAssignedToALooseFileIsItsActivePreset() {
        let app = AppModel.mock(.playingEpisode)
        let loose = MediaItem(url: URL(fileURLWithPath: "/tmp/Loose Clip.mp4"))
        XCTAssertNil(loose.episode)
        XCTAssertNil(loose.folder)
        let preset = app.presets.capture(name: "Loose", tracks: app.tracks, audio: app.audioEffects, video: app.videoEffects)
        app.presets.assign(preset.id, to: loose)
        XCTAssertEqual(app.presets.preset(for: loose)?.id, preset.id)
        XCTAssertNil(app.presets.preset(for: MediaItem(url: URL(fileURLWithPath: "/tmp/Other.mp4"))), "per file, not global")
    }
}
