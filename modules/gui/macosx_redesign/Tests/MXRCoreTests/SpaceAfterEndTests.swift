import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// Live finding (1-window run): at the end of the media the play icon shows, the Play button and
/// Playback > Play restart the item, but Space did nothing because VLC's play-pause hotkey only
/// pauses or resumes. Space must act like the Play button there.
@MainActor
final class SpaceAfterEndTests: XCTestCase {
    private func endedApp() throws -> (MockBackend, AppModel) {
        let mock = MockBackend(scenario: .playingEpisode)
        let app = mock.makeAppModel(clockTicks: false)
        let media = try XCTUnwrap(mock.player.currentMedia)
        // End of media: the item stays current, the player is stopped (play icon shown).
        mock.player.load(media, at: media.duration ?? .zero, state: .stopped)
        XCTAssertTrue(app.player.isStopped)
        XCTAssertFalse(app.player.isPlaying)
        return (mock, app)
    }

    func testSpaceAfterTheEndRestartsPlaybackLikeThePlayButton() throws {
        let (mock, app) = try endedApp()
        let space = try XCTUnwrap(KeyBinding(vlcString: "Space"))

        XCTAssertTrue(app.shortcuts.handle(space))
        XCTAssertTrue(app.player.isPlaying, "Space after the end starts the item again")
        XCTAssertEqual(mock.player.state, .playing)
        XCTAssertEqual(app.osd.message?.text, "Play")
        XCTAssertEqual(app.osd.message?.pressedKeyText, "Pressed Space")

        // While playing, Space is VLC's own pause hotkey again.
        XCTAssertTrue(app.shortcuts.handle(space))
        XCTAssertEqual(mock.player.state, .paused)
        XCTAssertEqual(mock.shortcuts.triggered.last, "play-pause")
    }

    func testPlaybackMenuPlayAfterTheEndStillRestarts() throws {
        let (mock, app) = try endedApp()
        app.perform(.playPause)
        XCTAssertEqual(mock.player.state, .playing)
    }
}
