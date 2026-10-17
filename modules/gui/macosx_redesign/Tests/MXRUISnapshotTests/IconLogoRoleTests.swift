import AppKit
import MXRDesign
import SwiftUI
import XCTest

/// S72: the VLC cone is painted with Figma `Accent/Logo` (Player - Light 2425:13629 uses
/// Light/Accent/Logo #C2711A), not `Accent/Main` (#E8851A in Light). Both are #D37918 in Dark.
@MainActor
final class IconLogoRoleTests: XCTestCase {
    func testLightConeIsAccentLogoInSwiftUI() throws {
        for scheme in [ColorScheme.light, .dark] {
            let pixel = try XCTUnwrap(Self.conePixel(scheme: scheme))
            Self.assert(pixel, equals: Theme.Color.accentLogo.value(scheme: scheme), "\(scheme) SwiftUI cone")
        }
        let light = try XCTUnwrap(Self.conePixel(scheme: .light))
        let main = Theme.Color.accentMain.value(scheme: .light)
        XCTAssertGreaterThan(abs(light.red - main.red) + abs(light.green - main.green), 0.08,
                             "The Light cone must not be Accent/Main \(main)")
    }

    func testLightConeIsAccentLogoInAppKit() throws {
        let image = MXRIcon.nsImage(.vlc, size: 48)
        for (name, scheme) in [(NSAppearance.Name.aqua, ColorScheme.light), (.darkAqua, .dark)] {
            let pixel = try XCTUnwrap(Self.sample(appearance: name, size: 48) { rect in
                image.draw(in: rect)
            })
            Self.assert(pixel, equals: Theme.Color.accentLogo.value(scheme: scheme), "\(name.rawValue) AppKit cone")
        }
    }

    /// S25–S27: the subtitle-file glyph has Figma's folded top-left corner (1911:8286), an edge the
    /// SVG export dropped: a vertical stroke at x 9 from the top side down to y 7.75, then left.
    func testSubtitleGlyphDrawsTheFoldedCorner() throws {
        let image = MXRIcon.nsImage(.subtitle, size: 48, tint: Theme.Color.fgA2)
        let rep = try XCTUnwrap(Self.srgbBitmap(pixels: 48))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            image.draw(in: NSRect(x: 0, y: 0, width: 48, height: 48))
            NSGraphicsContext.restoreGraphicsState()
        }
        func alpha(_ x: CGFloat, _ y: CGFloat) -> CGFloat { rep.colorAt(x: Int(x * 2), y: Int(y * 2))?.alphaComponent ?? 0 }
        XCTAssertGreaterThan(alpha(9, 5), 0.8, "fold edge (x 9, y 5) is missing")
        XCTAssertGreaterThan(alpha(5.5, 7.75), 0.8, "fold edge (x 5.5, y 7.75) is missing")
        XCTAssertLessThan(alpha(12, 8), 0.1, "the page itself stays open")
    }

    private static func assert(_ pixel: Theme.RGBA, equals expected: Theme.RGBA, _ what: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pixel.red, expected.red, accuracy: 0.02, "\(what) \(pixel) is not \(expected)", file: file, line: line)
        XCTAssertEqual(pixel.green, expected.green, accuracy: 0.02, "\(what) \(pixel) is not \(expected)", file: file, line: line)
        XCTAssertEqual(pixel.blue, expected.blue, accuracy: 0.02, "\(what) \(pixel) is not \(expected)", file: file, line: line)
    }

    /// The cone drawn by `MXRIcon` as the player bars use it (passing the old `accentLogo` tint, which
    /// only colors gray artwork), in a window of the given scheme.
    private static func conePixel(scheme: ColorScheme) -> Theme.RGBA? {
        _ = NSApplication.shared
        let size: CGFloat = 48
        let view = MXRIcon(.vlc, size: size, tint: Theme.Color.fgA2)
            .environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: size, height: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = hosting
        defer { window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        window.displayIfNeeded()
        // Capture into an sRGB bitmap, as mxr-snapshot does, so the pixel is the drawn sRGB value.
        guard let rep = srgbBitmap(pixels: Int(size) * 2) else { return nil }
        rep.size = NSSize(width: size, height: size)
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return pixel(rep, size: size)
    }

    private static func sample(appearance: NSAppearance.Name, size: CGFloat, draw: @escaping (NSRect) -> Void) -> Theme.RGBA? {
        guard let rep = srgbBitmap(pixels: Int(size)), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            draw(NSRect(x: 0, y: 0, width: size, height: size))
            NSGraphicsContext.restoreGraphicsState()
        }
        return pixel(rep, size: size)
    }

    private static func srgbBitmap(pixels: Int) -> NSBitmapImageRep? {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB)
    }

    /// A pixel in the solid base of the cone (icon units x 12, y 19 of 24; y from the top).
    private static func pixel(_ rep: NSBitmapImageRep, size: CGFloat) -> Theme.RGBA? {
        let x = Int(12 / 24 * CGFloat(rep.pixelsWide))
        let y = Int(19 / 24 * CGFloat(rep.pixelsHigh))
        guard let color = rep.colorAt(x: x, y: y) else { return nil }
        return Theme.RGBA(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent,
                          alpha: color.alphaComponent)
    }
}
