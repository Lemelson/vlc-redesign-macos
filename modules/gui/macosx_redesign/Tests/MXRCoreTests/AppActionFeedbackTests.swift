import XCTest
@testable import MXRCore
@testable import MXRMockBackend

/// D027: an app action run from its key shows the same two-line OSD as an engine action
/// ("Hide UI" / "Pressed ⌘\"), and a menu or tile running it shows nothing.
@MainActor
final class AppActionFeedbackTests: XCTestCase {
    func testKeyedAppActionsShowTheirResultNextToTheKey() throws {
        let app = AppModel.mock(.playingEpisode)
        let hideUI = try XCTUnwrap(KeyBinding(vlcString: "Command+\\"))

        XCTAssertTrue(app.shortcuts.handle(hideUI))
        XCTAssertTrue(app.interface.isUIHidden)
        XCTAssertEqual(app.osd.message?.text, "Hide UI")
        XCTAssertEqual(app.osd.message?.pressedKeyText, "Pressed ⌘\\")

        XCTAssertTrue(app.shortcuts.handle(hideUI))
        XCTAssertFalse(app.interface.isUIHidden)
        XCTAssertEqual(app.osd.message?.text, "Show UI", "the line says what the key just did")
        XCTAssertEqual(app.osd.message?.pressedKeyText, "Pressed ⌘\\")

        XCTAssertTrue(app.shortcuts.handle(try XCTUnwrap(KeyBinding(vlcString: "q"))))
        XCTAssertEqual(app.osd.message?.text, "Show Queue")
        XCTAssertEqual(app.osd.message?.pressedKeyText, "Pressed Q")
    }

    func testMenuTriggeredAppActionShowsNoOSD() {
        let app = AppModel.mock(.playingEpisode)
        app.shortcuts.trigger("app-hide-ui")
        XCTAssertTrue(app.interface.isUIHidden)
        XCTAssertNil(app.osd.message)
    }

    func testBlockedAppActionShowsOnlyTheKey() throws {
        let app = AppModel.mock(.playingEpisode)
        app.interface.isCustomizing = true
        XCTAssertTrue(app.shortcuts.handle(try XCTUnwrap(KeyBinding(vlcString: "Command+\\"))))
        XCTAssertFalse(app.interface.isUIHidden)
        XCTAssertNil(app.osd.message?.text, "nothing ran, so there is no result line")
    }
}
