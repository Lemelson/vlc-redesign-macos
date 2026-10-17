import AppKit
import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

@MainActor
final class PanelAuditRegressionTests: XCTestCase {
    func testOpacityEnablesBackgroundAndZeroDisablesIt() {
        var style = SubtitleStyle.default
        style.backgroundOpacity = 0.5
        XCTAssertTrue(style.background)
        XCTAssertEqual(style.backgroundOpacity, 0.5)
        style.backgroundOpacity = 0
        XCTAssertFalse(style.background)
        style.setBackgroundOpacity(2)
        XCTAssertEqual(style.backgroundOpacity, 1)
    }
    func testCommandSelectionUsesCapturedFlags() {
        XCTAssertEqual(PanelQueueInteraction.selection(current: [1], clicked: 2, modifiers: .command), [1, 2])
        XCTAssertEqual(PanelQueueInteraction.selection(current: [1, 2], clicked: 2, modifiers: .command), [1])
        XCTAssertEqual(PanelQueueInteraction.selection(current: [1], clicked: 2, modifiers: []), [2])
    }
    func testMoveDestinationAccountsForRemovalOfSource() {
        XCTAssertEqual(PanelQueueInteraction.moveDestination(index: 2, count: 4, direction: -1), 1)
        XCTAssertEqual(PanelQueueInteraction.moveDestination(index: 1, count: 4, direction: 1), 3)
        XCTAssertNil(PanelQueueInteraction.moveDestination(index: 0, count: 4, direction: -1))
        XCTAssertNil(PanelQueueInteraction.moveDestination(index: 3, count: 4, direction: 1))
    }
    func testHDRMenuDoesNotOfferUnsupportedOverrides() {
        let app = AppModel.mock(.pausedEpisode)
        // D039: only Auto applies; the manual modes are listed but disabled.
        XCTAssertEqual(MXRPlayerMenus.hdrModes(app).filter(\.isEnabled).map(\.title), ["Auto"])
    }
    func testPlayerPlaylistMenuOffersAddToPlaylist() {
        let app = AppModel.mock(.pausedEpisode)
        XCTAssertTrue(MXRPlayerMenus.playlist(app).contains { $0.title == "Add to Playlist" })
        let current = app.player.media!
        let destinations = MXRPlayerMenus.playlist(app).first { $0.title == "Add to Playlist" }?.children ?? []
        if case .action(let action) = destinations[0].kind { action() }
        XCTAssertEqual(app.interface.pendingPlaylistMedia.map(\.id), [current.id])
    }
    // D-07: a queue row adds itself, or the whole selection in queue order when it is part of one.
    func testQueueRowAddToPlaylistResolvesRowOrSelection() {
        let app = AppModel.mock(.pausedEpisode)
        let items = app.queue.items
        guard items.count > 2 else { return XCTFail("Fixture requires three queue rows") }
        app.queue.selection = [items[2].id, items[0].id]
        XCTAssertEqual(PanelQueueInteraction.media(for: items[2], in: app.queue).map(\.id), [items[0].media.id, items[2].media.id])
        XCTAssertEqual(PanelQueueInteraction.media(for: items[1], in: app.queue).map(\.id), [items[1].media.id])
        app.queue.selection = [items[1].id]
        XCTAssertEqual(PanelQueueInteraction.media(for: items[1], in: app.queue).map(\.id), [items[1].media.id])
    }
    func testArrowNavigationStaysWithinRows() {
        XCTAssertEqual(PanelQueueInteraction.neighbor(in: [1, 2, 3], current: 2, direction: .up), 1)
        XCTAssertEqual(PanelQueueInteraction.neighbor(in: [1, 2, 3], current: 2, direction: .down), 3)
        XCTAssertNil(PanelQueueInteraction.neighbor(in: [1, 2, 3], current: 1, direction: .up))
        XCTAssertNil(PanelQueueInteraction.neighbor(in: [1, 2, 3], current: 3, direction: .down))
    }
    func testKeyboardMoveUsesBackendInsertionSemantics() {
        let app = AppModel.mock(.pausedEpisode)
        let original = app.queue.items
        guard original.count > 1 else { return XCTFail("Fixture requires multiple queue rows") }
        let item = original[0]
        app.queue.move([item.id], to: PanelQueueInteraction.moveDestination(index: 0, count: original.count, direction: 1)!)
        XCTAssertEqual(app.queue.items[1].id, item.id)
        app.queue.move([item.id], to: PanelQueueInteraction.moveDestination(index: 1, count: original.count, direction: -1)!)
        XCTAssertEqual(app.queue.items.map(\.id), original.map(\.id))
    }
    func testOverflowKeepsNonCommandControlsAndDedicatedPanelActions() {
        let app = AppModel.mock(.pausedEpisode)
        let controls: [PlayerControl] = [.playbackSpeed, .hdr, .zoom, .pictureInPicture, .properties, .replay, .playlists, .chapters, .bookmarks]
        var pip = false
        let items = MXRPlayerMenus.overflow(controls, app: app, onPictureInPicture: { pip = true })
        XCTAssertEqual(items.count, controls.count)
        if case .action(let action) = items[3].kind { action() }
        XCTAssertTrue(pip)
        if case .action(let action) = items[7].kind { action() }
        XCTAssertEqual(app.interface.rightPanel, .queue(.chapters))
        if case .action(let action) = items[8].kind { action() }
        XCTAssertEqual(app.interface.rightPanel, .queue(.bookmarks))
    }

}
