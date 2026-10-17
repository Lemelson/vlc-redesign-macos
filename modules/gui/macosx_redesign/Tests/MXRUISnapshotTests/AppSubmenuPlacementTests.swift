import CoreGraphics
import MXRCore
@testable import MXRDesign
import MXRGalleryCatalog
import MXRMockBackend
@testable import MXRUI
import XCTest

/// S08 / S68: in the ⋯ menu compositions the submenu's first row is drawn level with the
/// highlighted parent row (``MXRPopupPlacement/beside``), for a row above the menu's separator
/// (Open Recent) as well as below it (Profile).
final class AppSubmenuPlacementTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    @MainActor
    func testOpenRecentSubmenuStartsLevelWithItsRow() throws {
        try assertSubmenuLevelWithHighlightedRow("S08.RecentSubmenu/default")
    }

    @MainActor
    func testProfileSubmenuStartsLevelWithItsRow() throws {
        try assertSubmenuLevelWithHighlightedRow("S68.ProfileSubmenu/movies")
    }

    /// Reads what was drawn: the parent's highlighted row (opaque BG/A2 over the translucent card)
    /// and the submenu card's top edge, then checks the submenu's first row starts on that row.
    @MainActor
    private func assertSubmenuLevelWithHighlightedRow(_ id: String, file: StaticString = #filePath,
                                                       line: UInt = #line) throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: id))
        let image = try GalleryRenderer.render(entry, scale: 1)
        let pixels = Self.alpha(image)
        func firstRow(x: Int, where test: (UInt8) -> Bool) -> Int? {
            (0..<image.height).first { test(pixels[$0 * image.width + x]) }
        }
        let inset = Int(Theme.Spacing.gap10)
        let parentX = inset
        let submenuX = Int(Theme.Metric.Menus.appMenu.width + Theme.Popup.submenuGap) + inset
        // The card fill is translucent (alpha ≈ 242); the hover/expanded row is opaque.
        let rowTop = try XCTUnwrap(firstRow(x: parentX) { $0 >= 254 }, "\(id): no highlighted row drawn", file: file, line: line)
        // The submenu's shadow above its top stays far below the card fill's alpha.
        let cardTop = try XCTUnwrap(firstRow(x: submenuX) { $0 >= 128 }, "\(id): no submenu card drawn", file: file, line: line)
        let firstSubmenuRow = cardTop + Int(MXRPopupStyle.contextMenu.padding.top)
        XCTAssertLessThanOrEqual(abs(firstSubmenuRow - rowTop), 1,
                                 "\(id): submenu's first row at \(firstSubmenuRow) pt, its parent row at \(rowTop) pt",
                                 file: file, line: line)
    }

    /// Alpha channel, top-left origin.
    private static func alpha(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 3, to: data.count, by: 4).map { data[$0] }
    }
}

/// S10: right-click › Subtitle › Subtitle Earlier / Later run VLC's subtitle delay step, so they
/// show VLC's subtitle delay keys like the other engine-key rows (D026), and follow a rebinding.
@MainActor
final class SubtitleDelayMenuShortcutTests: XCTestCase {
    func testEarlierAndLaterShowTheSubtitleDelayKeys() throws {
        let app = AppModel.mock(.playingEpisode)
        func row(_ title: String) throws -> MXRMenuItem {
            try XCTUnwrap(MXRPlayerMenus.subtitles(app).first { $0.title == title }, "\(title) row")
        }
        let earlier = try XCTUnwrap(app.shortcuts.primaryBinding(for: "subdelay-down"))
        let later = try XCTUnwrap(app.shortcuts.primaryBinding(for: "subdelay-up"))
        XCTAssertEqual(try row("Subtitle Earlier").shortcut, earlier)
        XCTAssertEqual(try row("Subtitle Later").shortcut, later)

        // Rebinding the engine key changes what the row shows.
        let rebound = try XCTUnwrap(KeyBinding(vlcString: "Command+Shift+h"))
        app.shortcuts.setBinding(rebound, for: "subdelay-down")
        app.shortcuts.saveDraft()
        XCTAssertEqual(try row("Subtitle Earlier").shortcut, rebound)
    }
}
