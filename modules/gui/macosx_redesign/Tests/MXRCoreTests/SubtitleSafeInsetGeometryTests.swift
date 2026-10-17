import CoreGraphics
import MXRCore
import XCTest

/// What the bridge's subtitle safe inset is measured from: VLC draws subtitles centred at the
/// bottom of the fitted picture, so only an overlay across its centre hides them and a
/// letterbox bar below the picture already keeps them clear of it.
final class SubtitleSafeInsetGeometryTests: XCTestCase {
    private let view = CGRect(x: 0, y: 0, width: 1600, height: 1000)

    func testAControlBarOverAFullHeightPictureCoversItsHeight() {
        let picture = SubtitleSafeInset.fittedPicture(videoSize: CGSize(width: 1600, height: 1000), in: view)
        XCTAssertEqual(picture, view)
        let bar = CGRect(x: 0, y: 920, width: 1600, height: 80)
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: [bar]), 80)
    }

    func testLetterboxBarsBelowThePictureAreSubtracted() {
        // 16:9 in 16:10: 50 pt bars above and below the 900 pt picture.
        let picture = SubtitleSafeInset.fittedPicture(videoSize: CGSize(width: 1920, height: 1080), in: view)
        XCTAssertEqual(picture.minY, 50, accuracy: 0.001)
        XCTAssertEqual(picture.height, 900, accuracy: 0.001)
        let bar = CGRect(x: 0, y: 920, width: 1600, height: 80)
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: [bar]), 30, accuracy: 0.001)
        let lowBar = CGRect(x: 0, y: 960, width: 1600, height: 40)
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: [lowBar]), 0, "the bar sits in the letterbox")
    }

    func testOnlyOverlaysAcrossThePictureCentreCount() {
        let picture = view
        let sidePanel = CGRect(x: 0, y: 60, width: 320, height: 940)
        let bar = CGRect(x: 0, y: 940, width: 1600, height: 60)
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: [sidePanel]), 0, "a panel at the side leaves the centred subtitle visible")
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: [sidePanel, bar]), 60)
        let tall = CGRect(x: 0, y: -100, width: 1600, height: 1200)
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: [tall]), 1000, "never more than the picture")
        XCTAssertEqual(SubtitleSafeInset.points(picture: picture, overlays: []), 0)
    }
}
