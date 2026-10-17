import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
@testable import MXRUI
import SwiftUI
import XCTest

/// Player - Light (2425:13624) draws its bars as BG/A3 Transparent (#D5D5D5 @ 0.75) over its
/// #2D2B29 video, which reads #ABABAA. The product keeps the picture between the pinned bars (D055),
/// so the bars are that tint over the canvas base (`MXRBackdropBase`, the frame's video colour) with
/// no material: over Light BG/B2 #DEDEDE they read #B1 offscreen and #BB live (A-05-S72), and with
/// a dark material over #090909 #A7 offscreen (D053).
@MainActor
final class LightBarBackdropTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    func testLightBarsAreTheTintOverADarkBase() throws {
        let image = try GalleryRenderer.render(try XCTUnwrap(GalleryCatalog.entry(id: "S72.Window/light")), scale: 1)
        let pixels = try BarPixels(image)
        // Empty stretches of the top bar (y 10–30) and of the control bar (bottom 20 pt).
        let points = [(600, 10), (900, 25), (1100, 30), (1500, image.height - 20), (700, image.height - 8)]
        for (x, y) in points {
            let (r, g, b) = pixels.color(x: x, y: y)
            for channel in [r, g, b] {
                XCTAssertLessThanOrEqual(abs(channel - 0xAB), 1, "bar at (\(x), \(y)) reads \(r),\(g),\(b), Figma #ABABAA")
            }
        }
    }

    /// The pinned bar is Figma's stack (tint over the canvas base) whatever lies under it, so the
    /// live window, which composites a real `NSVisualEffectView`, cannot differ from the offscreen
    /// render: no material is drawn, and content under the surface does not show through.
    func testPinnedBarSurfaceIgnoresWhatIsBehindIt() throws {
        for behind in [Color.white, Color.black, Color.red] {
            let view = ZStack {
                behind
                MXRBackdropSurface(tint: Theme.Color.bgA3Transparent, material: .headerView, overCanvasBase: true)
            }
            .frame(width: 40, height: 20)
            .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 20), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            XCTAssertFalse(host.containsVisualEffectView, "a pinned bar draws no material")
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 20, bitsPerSample: 8,
                                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
                .retagging(with: .sRGB))
            host.cacheDisplay(in: host.bounds, to: rep)
            let pixels = try BarPixels(try XCTUnwrap(rep.cgImage))
            let (r, g, b) = pixels.color(x: 20, y: 10)
            XCTAssertEqual([r, g, b].map { abs($0 - 0xAB) <= 1 }, [true, true, true],
                           "over \(behind) the pinned Light bar reads \(r),\(g),\(b), Figma #ABABAA")
        }
    }
}

private extension NSView {
    var containsVisualEffectView: Bool {
        self is NSVisualEffectView || subviews.contains { $0.containsVisualEffectView }
    }
}

private struct BarPixels {
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
