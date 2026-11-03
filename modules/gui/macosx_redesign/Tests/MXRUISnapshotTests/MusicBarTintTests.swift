import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
@testable import MXRUI
import SwiftUI
import XCTest

/// Player - Music (4767:23726) draws its control bar as BG/A3 Transparent (style 1702:4100,
/// #191919 @ 0.95) over the black canvas above the bar, which reads #171717. The product's bar lies
/// over its own blurred artwork or that black canvas, so it is the tint over them; the
/// `NSVisualEffectView` material added its own colour under the tint (#191919, critic P2, D056).
@MainActor
final class MusicBarTintTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    func testMusicBarIsTheTintOverTheBlackCanvas() throws {
        for id in ["S34.Player/music", "S34.Player/music-waveform"] {
            let image = try GalleryRenderer.render(try XCTUnwrap(GalleryCatalog.entry(id: id)), scale: 1)
            let pixels = try MusicBarPixels(image)
            // Empty stretches of the 66 pt control bar: left of previous, beside the queue, above the cone.
            for (x, y) in [(50, image.height - 30), (1500, image.height - 5), (1850, image.height - 50)] {
                let (r, g, b) = pixels.color(x: x, y: y)
                for channel in [r, g, b] {
                    XCTAssertLessThanOrEqual(abs(channel - 0x17), 1, "\(id) bar at (\(x), \(y)) reads \(r),\(g),\(b), Figma #171717")
                }
            }
        }
    }
}

private struct MusicBarPixels {
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
}
