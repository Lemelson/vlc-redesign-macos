import MXRCore
import MXRMockBackend
@testable import MXRUI
import XCTest

/// LIVE (live2 D-shadow-pip-wording): right-click ▸ Playback ▸ Renderer named the local output
/// "This Mac" while the Video sidebar's Render dropdown said "Local". Both now use Figma's word
/// (Render dropdown, Frame 117 "Local"; VLC's Qt renderer menu says "<Local>").
@MainActor
final class RendererWordingTests: XCTestCase {
    func testRendererMenuNamesTheLocalOutputLikeTheSidebar() throws {
        let app = AppModel.mock(.playingMovie)
        let rows = MXRPlayerMenus.renderers(app)
        let local = try XCTUnwrap(rows.first)
        XCTAssertEqual(local.title, "Local")
        XCTAssertEqual(local.title, MXRPlayerMenus.localRendererTitle, "the sidebar's Render dropdown reads the same constant")
        XCTAssertTrue(local.isChecked, "nothing is cast: the local output is checked")
        XCTAssertFalse(rows.contains { $0.title == "This Mac" })
    }
}
