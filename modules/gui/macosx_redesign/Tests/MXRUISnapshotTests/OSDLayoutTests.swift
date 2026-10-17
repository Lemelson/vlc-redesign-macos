import CoreGraphics
import MXRDesign
import XCTest

/// B-08: the OSD scales with the picture the vout draws and keeps a margin that grows with its text.
final class OSDLayoutTests: XCTestCase {
    func testPictureHeightIgnoresTheLetterbox() {
        let container = CGSize(width: 1728, height: 900)
        // 2.35:1 in a 1.92:1 area: bars above and below; the picture is 1728 / 2.35 tall.
        XCTAssertEqual(Theme.OSD.pictureHeight(container: container, videoSize: CGSize(width: 1920, height: 817)),
                       1728 * 817 / 1920, accuracy: 0.01)
        // 4:3 in the same area: pillarboxed, the picture fills the height.
        XCTAssertEqual(Theme.OSD.pictureHeight(container: container, videoSize: CGSize(width: 640, height: 480)), 900)
        XCTAssertEqual(Theme.OSD.pictureHeight(container: container, videoSize: nil), 900)
    }

    func testMarginFollowsTheTitleSize() {
        XCTAssertEqual(Theme.OSD.margin(videoHeight: 0), Theme.Font.osdTitle.size * Theme.OSD.marginToTitle)
        let tall = Theme.OSD.margin(videoHeight: 1000)
        XCTAssertEqual(tall, Theme.OSD.styles(videoHeight: 1000).title.size * Theme.OSD.marginToTitle)
        XCTAssertGreaterThan(tall, Theme.OSD.margin(videoHeight: 0))
    }
}
