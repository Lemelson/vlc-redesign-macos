import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
@testable import MXRUI
import XCTest

/// Customize keeps the paused video visible behind the palette (§15). Player - customize
/// (2107:5604) uses the same video fill as Player (187:328), and key frame 19m12.4 shows the video
/// through the dialog, so no flat gray covers the video while editing.
@MainActor
final class CustomizationBackdropTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    func testCustomizeDoesNotCoverTheVideo() throws {
        let editing = try RGBPixels(GalleryRenderer.render(
            try XCTUnwrap(GalleryCatalog.entry(id: "S66.Window/customization")), scale: 1))
        let playing = try RGBPixels(GalleryRenderer.render(
            try XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/shipping")), scale: 1))
        // Video area left of the palette and below the top bar, above the bars and the band.
        let points = [(60, 140), (200, 400), (300, 700), (1700, 300), (1800, 700)]
        for (x, y) in points {
            XCTAssertTrue(editing.near(x: x, y: y, playing.color(x: x, y: y), tolerance: 2),
                          "video at (\(x), \(y)) is the same while customizing")
        }
    }
}

private struct RGBPixels {
    let width: Int
    let data: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        data = buffer
    }

    func color(x: Int, y: Int) -> (Int, Int, Int) {
        let index = (y * width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    func near(x: Int, y: Int, _ expected: (Int, Int, Int), tolerance: Int) -> Bool {
        let actual = color(x: x, y: y)
        return abs(actual.0 - expected.0) <= tolerance && abs(actual.1 - expected.1) <= tolerance
            && abs(actual.2 - expected.2) <= tolerance
    }
}
