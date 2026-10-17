import XCTest
import MXRCore
import MXRDesign
@testable import MXRUI

final class PlayerProgressRegressionTests: XCTestCase {
    /// B-04: only pixel filters the still cannot reproduce turn it off; geometry, renderer,
    /// resolution, deinterlacing and the fit-to-window zoom the engine reports by default do not.
    func testPausedStillStaysOnForGeometryAndOffForPixelFilters() {
        XCTAssertTrue(PausedStillLayout.allowsStill(effects: .default))
        var effects = VideoEffects.default
        effects.zoom = .fitWindow
        effects.crop = "2.35:1"; effects.aspectRatio = "4:3"; effects.rotation = 90; effects.flip = .horizontal
        effects.rendererID = "chromecast"; effects.resolution = "720p"; effects.deinterlace = .off
        effects.cropInsets = CropInsets(top: 10, bottom: 10, left: 0, right: 0)
        XCTAssertTrue(PausedStillLayout.allowsStill(effects: effects))
        effects.essential.isEnabled = true
        XCTAssertTrue(PausedStillLayout.allowsStill(effects: effects), "Enabled essentials at neutral values change nothing")
        effects.essential.brightness = 1.4
        XCTAssertFalse(PausedStillLayout.allowsStill(effects: effects))
        var colors = VideoEffects.default
        colors.colors.sepia = true
        XCTAssertFalse(PausedStillLayout.allowsStill(effects: colors))
    }

    func testPausedStillLetterboxesLikeTheVout() {
        let image = CGSize(width: 1920, height: 1080)
        var effects = VideoEffects.default
        effects.zoom = .fitWindow
        let fit = PausedStillLayout(image: image, source: image, effects: effects, container: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(fit.displaySize.width, 1000, accuracy: 0.01)
        XCTAssertEqual(fit.displaySize.height, 562.5, accuracy: 0.01)
        XCTAssertEqual(fit.cropOrigin, .zero)

        effects.crop = "2.35:1"
        let cropped = PausedStillLayout(image: image, source: image, effects: effects, container: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(cropped.displaySize.width / cropped.displaySize.height, 2.35, accuracy: 0.001)
        XCTAssertEqual(cropped.displaySize.width, 1000, accuracy: 0.01)
        XCTAssertEqual(cropped.imageSize.width, 1000, accuracy: 0.01, "A ratio crop keeps the full width")
        XCTAssertEqual(cropped.cropOrigin.y, (cropped.imageSize.height - cropped.displaySize.height) / 2, accuracy: 0.01)

        effects.crop = nil
        effects.aspectRatio = "4:3"
        let stretched = PausedStillLayout(image: image, source: image, effects: effects, container: CGSize(width: 1600, height: 900))
        XCTAssertEqual(stretched.displaySize.width / stretched.displaySize.height, 4.0 / 3, accuracy: 0.001)
        XCTAssertEqual(stretched.displaySize.height, 900, accuracy: 0.01)

        effects.aspectRatio = nil
        effects.zoom = .half
        let zoomed = PausedStillLayout(image: CGSize(width: 960, height: 540), source: image, effects: effects,
                                       container: CGSize(width: 1600, height: 900))
        XCTAssertEqual(zoomed.displaySize.width, 960, accuracy: 0.01, "1:2 draws the 1920-pixel source 960 points wide")
    }

    func testWaveformFillEndsAtHeadLeadingEdgeAcrossTrack() {
        for progress in [0.0, 0.5, 1.0] {
            XCTAssertEqual(PlayerGeometry.seekHeadX(progress: progress, width: 996, headWidth: 8), 2 + 988 * progress, accuracy: 0.001)
        }
    }
    func testAnimationStopsForHiddenPiPAndReducedMotion() {
        XCTAssertTrue(PlayerGeometry.animatesSeek(running: true, barsVisible: true, hidden: false, pip: false, reduceMotion: false))
        XCTAssertFalse(PlayerGeometry.animatesSeek(running: true, barsVisible: true, hidden: false, pip: true, reduceMotion: false))
        XCTAssertFalse(PlayerGeometry.animatesSeek(running: true, barsVisible: true, hidden: false, pip: false, reduceMotion: true))
        XCTAssertFalse(PlayerGeometry.animatesSeek(running: true, barsVisible: false, hidden: false, pip: false, reduceMotion: false))
    }
    // The folder-width arithmetic test moved to WindowCompositionTests.testNarrowTopBarHidesTheTitleInsteadOfAnEllipsis (A-09).
}
