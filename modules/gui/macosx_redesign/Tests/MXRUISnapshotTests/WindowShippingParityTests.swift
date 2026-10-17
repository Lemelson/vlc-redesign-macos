import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Final-polish parity items of the window composition: the Customize new-row band (S66), the
/// shipping-window engine on App entries (modal host, titlebar) and the render context.
@MainActor
final class WindowShippingParityTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    // MARK: S66 edit-mode band (2107:5604, 19m12.4)

    func testCustomizeDrawsAnEmptyBarRowAboveAOneRowControlBar() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S66.Window/customization"))
        let pixels = try RGBPixels(GalleryRenderer.render(entry, scale: 1))
        let row = Theme.Metric.ControlBar.bar.height
        let height = Int(Theme.Metric.Window.player.height)
        let bandMiddle = height - Int(row * 1.5), barRow = height - Int(row / 2), dimmed = height - Int(row * 3)
        // 972–1026: the band is the bar material (#191919 in Figma), not the video above it.
        XCTAssertTrue(pixels.near(x: 600, y: bandMiddle, pixels.color(x: 600, y: barRow + 20)), "band reads as a bar row")
        XCTAssertFalse(pixels.near(x: 600, y: bandMiddle, pixels.color(x: 600, y: dimmed), tolerance: 6), "band is not the dim")
        // Its top divider sits at 972, a second one at 1026 above the control bar.
        for divider in [height - Int(row * 2), height - Int(row)] {
            XCTAssertFalse(pixels.near(x: 600, y: divider, pixels.color(x: 600, y: bandMiddle), tolerance: 3),
                           "divider at y \(divider)")
        }
    }

    func testDroppingOnTheBandStartsANewRowNearestTheVideo() throws {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        let original = try XCTUnwrap(app.playerLayout.bottom.first)
        XCTAssertTrue(MXRLayoutDragPayload.tile(.favorite).place(in: .newFirstRow, at: 0, app: app))
        XCTAssertEqual(app.playerLayout.bottom.map { $0.map(\.control) }, [[.favorite], original.map(\.control)])
        // 19m26.3 → 19m27.6: moving the time group up builds the full-width seek row.
        let seek = try XCTUnwrap(app.playerLayout.bottom[1].first { $0.control == .seekBar })
        XCTAssertTrue(MXRLayoutDragPayload.placed(seek).place(in: .bottom(0), at: 1, app: app))
        XCTAssertEqual(app.playerLayout.bottom[0].map(\.control), [.favorite, .seekBar])
        XCTAssertFalse(app.playerLayout.bottom[1].contains { $0.control == .seekBar })
    }

    func testTwoRowLayoutGetsNoExtraBandWhileEditing() throws {
        let app = AppModel.mock(.pausedEpisode)
        app.beginCustomizing()
        app.layouts.updateDraft { $0 = .twoRowExample }
        XCTAssertEqual(PlayerGeometry.controlRows(layoutRows: app.playerLayout.bottom.count, customizing: true), 2)
        XCTAssertEqual(PlayerGeometry.controlRows(layoutRows: 1, customizing: false), 1)
    }

    // MARK: Shipping-window engine on App entries

    func testShippingEngineOnAnAppEntryKeepsTheTitlebarAndCentresTheDialog() throws {
        // parity group 7: the dialog's top was clipped (−20…520) and the top bar missing because the
        // App entry kept its fixed-frame wrapper inside the titled window.
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S37.App/convert-compact"))
        let ship = try RGBPixels(GalleryRenderer.render(entry, scale: 1, engine: .shippingWindow))
        let host = try RGBPixels(GalleryRenderer.render(entry, scale: 1, engine: .hostingView))
        // The dialog (40…500 in the 540 pt window, clear of the top bar) is where the hosting render puts it.
        let top = Int(Theme.Metric.topBarHeight)
        for y in [top + 2, top + 25, top + 60, 498] {
            XCTAssertTrue(ship.near(x: 300, y: y, host.color(x: 300, y: y), tolerance: 4), "dialog row \(y)")
        }
        XCTAssertFalse(ship.near(x: 300, y: top / 2, ship.color(x: 300, y: top + 2), tolerance: 2),
                       "the top bar shows above the dialog")
    }

    func testShippingEngineOnAnAppEntryKeepsTheConeClearOfTheTrafficLights() throws {
        let app = try XCTUnwrap(GalleryCatalog.entry(id: "S28.App/compact"))
        let window = try XCTUnwrap(GalleryCatalog.entry(id: "S28.Window/compact-queue"))
        let shipped = try RGBPixels(GalleryRenderer.render(app, scale: 1, engine: .shippingWindow))
        let reference = try RGBPixels(GalleryRenderer.render(window, scale: 1))
        // The left group (traffic lights, cone, menu, sidebar toggle) is drawn at the same place.
        let reserve = Int(ShippingWindowControls.measured.reserve)
        var differing = 0
        for x in stride(from: 4, to: reserve + 60, by: 2) {
            for y in stride(from: 8, to: 32, by: 2) where !shipped.near(x: x, y: y, reference.color(x: x, y: y), tolerance: 8) {
                differing += 1
            }
        }
        XCTAssertLessThan(differing, 4, "cone and traffic lights match the Window entry")
    }

    func testSchemeOverrideReachesWindowEntries() throws {
        // parity group 1: `--scheme light` had no effect because MXRAppView themes itself from the model.
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/pip"))
        let dark = try RGBPixels(GalleryRenderer.render(entry, scale: 1))
        let light = try RGBPixels(GalleryRenderer.render(entry, scale: 1, environment: GalleryEnvironment(colorScheme: .light)))
        // The placeholder itself is the dark video background in both schemes (D042); the bars follow the scheme.
        XCTAssertFalse(light.near(x: 1400, y: 20, dark.color(x: 1400, y: 20), tolerance: 20), "the top bar follows the scheme")
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

    func near(x: Int, y: Int, _ expected: (Int, Int, Int), tolerance: Int = 3) -> Bool {
        let actual = color(x: x, y: y)
        return abs(actual.0 - expected.0) <= tolerance && abs(actual.1 - expected.1) <= tolerance
            && abs(actual.2 - expected.2) <= tolerance
    }
}
