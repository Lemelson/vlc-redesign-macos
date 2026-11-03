import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
@testable import MXRUI
import XCTest

/// S71 with the bindings the installed app has (VLC's macOS engine defaults, D026): the keycaps use
/// Mac glyphs and nothing is squeezed out of a row. With separate keycaps per key and no fixed size,
/// "⌥ ⌘ ← / ⌥ ⌘ →" overflowed the row and SwiftUI drew empty keycaps and dropped the "/".
@MainActor
final class OnboardingShortcutKeycapTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    /// One keycap style on the whole screen (critic, S71): every binding is one keycap, paired or not.
    func testKeycapsUseMacGlyphsAndEveryBindingIsOneKeycap() throws {
        let app = AppModel.mock(.pausedEpisode)
        let seek = try XCTUnwrap(app.shortcuts.primaryBinding(for: "jump-short"))
        XCTAssertEqual(seek.onboardingKeycap, "⌥⌘←")
        let record = try XCTUnwrap(app.shortcuts.primaryBinding(for: "record"))
        XCTAssertEqual(record.onboardingKeycap, "⇧⌘R")
        for row in MXROnboardingShortcut.rows {
            for binding in row.bindings(in: app.shortcuts) {
                XCTAssertFalse(binding.onboardingKeycap.contains("SHIFT"), row.title)
            }
        }
    }

    /// A row with one modifier binding draws one keycap, as the paired rows do: the Record row's
    /// "⇧⌘R" is one run of glyphs, not three keycaps with gaps between them.
    func testSingleBindingRowIsOneKeycap() throws {
        let image = try GalleryRenderer.render(try XCTUnwrap(GalleryCatalog.entry(id: "S71.Onboarding/shortcuts")), scale: 1)
        let o = Theme.Metric.Onboarding.self
        let rowTop = o.shortcutTitleTop + o.shortcutTitle.height + o.shortcutColumnsGapAbove
            + 5 * (o.shortcutColumnsRowHeight + o.shortcutColumnsRowGap) // the sixth row of the right column: Record
        let keysX = o.shortcutColumnsLeading + o.shortcutColumnsColumnWidth + o.shortcutColumns.gap
            + o.shortcutColumnsLabelWidth + o.shortcutColumnsLabelGap
        let dark = try darkColumns(image, y: Int(rowTop + o.shortcutColumnsRowHeight / 2), x: Int(keysX),
                                   width: Int(CGFloat(image.width) - keysX))
        // Keycap fills are lighter than the dialog: one keycap is one run of keycap columns.
        let keycaps = dark.split(whereSeparator: { $0 }).filter { $0.count > 4 }.count
        XCTAssertEqual(keycaps, 1, "⇧⌘R is one keycap")
    }

    /// S70's System tile split is antialiased along its diagonal (parity: a two-stop hard gradient
    /// stair-stepped it): every row through the tile has a pixel between the two fills.
    func testSystemThemeTileDiagonalIsAntialiased() throws {
        let image = try GalleryRenderer.render(try XCTUnwrap(GalleryCatalog.entry(id: "S70.Onboarding/orange")), scale: 2)
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func gray(_ x: Int, _ y: Int) -> UInt8 { buffer[(y * image.width + x) * 4] }
        // The third (System) tile: the rightmost run of the light fill #AFAFAF on the tiles' middle row.
        let light: UInt8 = 0xAF, dark: UInt8 = 0x22
        let middle = (0..<image.height).first { y in (0..<image.width).contains { gray($0, y) == light } && y > image.height / 3 } ?? 0
        let tileRow = middle + 100
        let right = try XCTUnwrap((0..<image.width).last { gray($0, tileRow) == light })
        let left = max(0, right - Int(Theme.Metric.Dialogs.themeTile.width * 2))
        var steppedRows = 0, rows = 0
        for y in stride(from: middle + 20, to: middle + 180, by: 1) {
            let line = (left...right).map { gray($0, y) }
            guard line.contains(light), line.contains(dark) else { continue }
            rows += 1
            if !line.contains(where: { $0 > dark + 8 && $0 < light - 8 }) { steppedRows += 1 }
        }
        XCTAssertGreaterThan(rows, 100)
        XCTAssertLessThan(steppedRows, rows / 10, "the diagonal has antialiased edge pixels")
    }

    private func darkColumns(_ image: CGImage, y: Int, x: Int, width: Int) throws -> [Bool] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let row = y
        return (x..<min(image.width, x + width)).map { column in
            let i = (row * image.width + column) * 4
            return max(buffer[i], buffer[i + 1], buffer[i + 2]) < 22 // the dialog (BG/B1), not a keycap (BG/A3) or its edge
        }
    }

    /// Every keycap of the left column draws its glyphs: each keycap of the seek row is a light
    /// glyph on a keycap, and the "/" between the two bindings is drawn.
    func testSeekRowDrawsBothKeycapsAndTheSeparator() throws {
        let app = AppModel.mock(.pausedEpisode)
        XCTAssertEqual(app.shortcuts.primaryBinding(for: "jump+short")?.displayString, "⌥⌘→",
                       "the mock reports VLC's macOS defaults")
        let image = try GalleryRenderer.render(try XCTUnwrap(GalleryCatalog.entry(id: "S71.Onboarding/shortcuts")), scale: 1)
        let o = Theme.Metric.Onboarding.self
        let rowTop = o.shortcutTitleTop + o.shortcutTitle.height + o.shortcutColumnsGapAbove
            + o.shortcutColumnsRowHeight + o.shortcutColumnsRowGap // the second row: Seek Backward / Forward
        let keysX = o.shortcutColumnsLeading + o.shortcutColumnsLabelWidth + o.shortcutColumnsLabelGap
        let bright = try brightColumns(image, y: Int(rowTop), height: Int(o.shortcutColumnsRowHeight),
                                       x: Int(keysX), width: Int(o.shortcutColumns.gap + o.shortcutColumnsColumnWidth - keysX + o.shortcutColumnsLeading))
        // Glyph runs: "⌥⌘←", "/", "⌥⌘→" are three separate groups of bright columns.
        let groups = bright.split(whereSeparator: { !$0 }).count
        XCTAssertGreaterThanOrEqual(groups, 3, "the seek row draws two keycap labels and the separator")
    }

    private func brightColumns(_ image: CGImage, y: Int, height: Int, x: Int, width: Int) throws -> [Bool] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (x..<min(image.width, x + width)).map { column in
            (y..<min(image.height, y + height)).contains { row in
                let i = (row * image.width + column) * 4
                return min(buffer[i], buffer[i + 1], buffer[i + 2]) > 90 // glyphs (FG/1) and the "/" (FG/A3 #6B), not keycap fills or edges
            }
        }
    }
}
