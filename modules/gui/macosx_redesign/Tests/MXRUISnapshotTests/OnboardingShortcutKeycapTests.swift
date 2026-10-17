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

    func testKeycapsUseMacGlyphsAndPairedBindingsAreOneKeycap() throws {
        let app = AppModel.mock(.pausedEpisode)
        let seek = try XCTUnwrap(app.shortcuts.primaryBinding(for: "jump-short"))
        XCTAssertEqual(seek.onboardingKeycaps(pairedWithAnother: true), ["⌥⌘←"])
        let record = try XCTUnwrap(app.shortcuts.primaryBinding(for: "record"))
        XCTAssertEqual(record.onboardingKeycaps(pairedWithAnother: false), ["⇧", "⌘", "R"])
        for row in MXROnboardingShortcut.rows {
            for binding in row.bindings(in: app.shortcuts) {
                XCTAssertFalse(binding.onboardingKeycaps(pairedWithAnother: false).contains("SHIFT"), row.title)
            }
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
