import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Final-polish wave (2026-10-17) of the window composition: the saved two-row layout (S67), the
/// compact library beside a right panel in narrow windows (D057), the narrow resume toast (D051),
/// the Light PiP placeholder (D042/D053) and the fullscreen strip tracking (D055).
@MainActor
final class WindowFinalPolishTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    // MARK: S67 saved two-row layout (2160:8301, 19m27.6)

    func testTwoRowLayoutCentresTheTransportOnTheWindow() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S67.Window/two-row"))
        let pixels = try Pixels(GalleryRenderer.render(entry, scale: 1))
        // The play button is the accent fill in the lower row; Figma 2160:8310 spans 935–985 (centre 960).
        let y = Int(Theme.Metric.Window.player.height - Theme.Metric.ControlBar.bar.height / 2)
        let accent = (0..<pixels.width).filter { pixels.isAccent(x: $0, y: y) }
        let first = try XCTUnwrap(accent.first), last = try XCTUnwrap(accent.last)
        XCTAssertEqual(Double(first + last) / 2, Double(Theme.Metric.Window.player.width) / 2, accuracy: 2,
                       "the transport sits at the window's centre, not halfway between the clusters")
        XCTAssertEqual(Double(last - first + 1), Double(Theme.Metric.ControlBar.playButton.width), accuracy: 2)
    }

    func testRowWidthsCentreTheRunBetweenTwoSpacers() {
        // [left 300] spacer [run 130] spacer [right 200] in a 1880 pt row (Figma's two-row bar).
        let widths: [CGFloat] = [300, 0, 130, 0, 200], gaps: [CGFloat] = [0, 20, 20, 20, 20]
        let result = PlayerGeometry.rowWidths(widths, gaps: gaps, spacers: [1, 3], flexible: [1, 3], width: 1880)
        let runStart = widths[0] + gaps[1] + result[1] + gaps[2]
        XCTAssertEqual(runStart + 130 / 2, 940, accuracy: 0.001, "the run is centred on the row")
        XCTAssertEqual(result[1] + result[3], 1880 - 300 - 130 - 200 - 80, accuracy: 0.001, "spacers share the free width")
        XCTAssertNotEqual(result[1], result[3], "unequal clusters need unequal spacers")
        // Not enough room to centre: the run moves only as far as the free width allows.
        let tight = PlayerGeometry.rowWidths([900, 0, 130, 0, 100], gaps: gaps, spacers: [1, 3], flexible: [1, 3], width: 1300)
        XCTAssertEqual(tight[1], 0)
        XCTAssertEqual(tight[3], 1300 - 900 - 130 - 100 - 80)
        // One spacer, or a seek bar beside spacers: equal shares as before.
        let one = PlayerGeometry.rowWidths([100, 0, 100], gaps: [0, 8, 8], spacers: [1], flexible: [1], width: 500)
        XCTAssertEqual(one[1], 284)
    }

    func testHeaderClusterKeepsItsFigmaSpacingInAControlRow() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S67.Window/two-row"))
        let pixels = try Pixels(GalleryRenderer.render(entry, scale: 1))
        let rows = (1042...1064)
        // 2160:8404: ⋯ 21, sidebar 59, divider 87, folder 111 (glyph at 115) — no transport gaps.
        let folder = try XCTUnwrap((100..<140).first { x in rows.contains { pixels.isBright(x: x, y: $0) } })
        XCTAssertEqual(folder, 115, accuracy: 2, "the folder chip follows the divider without a gap")
        // 2160:8419: the title cell (text at 190) and the heart (glyph at 324) follow it.
        let title = try XCTUnwrap((170..<200).first { x in rows.contains { pixels.isBright(x: x, y: $0) } })
        XCTAssertEqual(title, 190, accuracy: 2)
    }

    // MARK: D057 compact library beside a right panel

    func testCompactLibraryNeverDropsBelowItsMinimumAndYieldsToAPanelInANarrowWindow() {
        let minimum = LibraryGeometry.compactMinimumWidth
        XCTAssertEqual(PlayerGeometry.compactLibraryWidth(windowWidth: 1920, panelOpen: true), Theme.Metric.Library.sidebar.width)
        XCTAssertEqual(PlayerGeometry.compactLibraryWidth(windowWidth: 1920, panelOpen: false), Theme.Metric.Library.sidebar.width)
        for width in stride(from: 480 as CGFloat, through: 1920, by: 16) {
            for panel in [false, true] {
                let library = PlayerGeometry.compactLibraryWidth(windowWidth: width, panelOpen: panel)
                XCTAssertTrue(library == 0 || library >= minimum, "\(width) pt, panel \(panel): \(library) pt")
                guard panel, library > 0 else { continue }
                let frame = PlayerGeometry.rightPanelFrame(.queue(.queue), in: CGSize(width: width, height: 800), controlHeight: 54,
                                                           leadingInset: library)
                XCTAssertEqual(frame.width, Theme.Metric.sidePanelWidth, "\(width) pt: the panel keeps its width beside the library")
                XCTAssertGreaterThanOrEqual(frame.minX, library, "\(width) pt: the panel never covers the library")
            }
        }
        // 480 pt (the window minimum): the library alone fits; with a panel it yields.
        XCTAssertGreaterThanOrEqual(PlayerGeometry.compactLibraryWidth(windowWidth: 480, panelOpen: false), minimum)
        XCTAssertEqual(PlayerGeometry.compactLibraryWidth(windowWidth: 480, panelOpen: true), 0)
    }

    func testNarrowWindowLibraryYieldsToThePanelAndComesBack() {
        let interface = InterfaceModel()
        interface.library = .compact
        interface.toggleQueuePanel(.queue)
        interface.reconcileLibraryAndPanel(fit: false)
        XCTAssertEqual(interface.library, .hidden, "the library yields to the panel just opened")
        XCTAssertTrue(interface.libraryYieldedToPanel)
        interface.closeRightPanel()
        interface.reconcileLibraryAndPanel(fit: false)
        XCTAssertEqual(interface.library, .compact, "and comes back when the panel closes")
        XCTAssertFalse(interface.libraryYieldedToPanel)
        // Opening the library while a panel is open closes the panel instead.
        interface.library = .hidden
        interface.toggleSidebar(.playback)
        interface.library = .compact
        interface.reconcileLibraryAndPanel(fit: false, libraryOpened: true)
        XCTAssertNil(interface.rightPanel)
        XCTAssertEqual(interface.library, .compact)
        // A window wide enough for both changes nothing.
        interface.toggleQueuePanel(.queue)
        interface.reconcileLibraryAndPanel(fit: true)
        XCTAssertEqual(interface.library, .compact)
        XCTAssertNotNil(interface.rightPanel)
    }

    // MARK: D051 narrow resume toast

    func testNarrowResumeToastUsesTheShortLabelInsteadOfTruncating() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S12.Window/continue-minimum"))
        let pixels = try Pixels(GalleryRenderer.render(entry, scale: 1))
        let size = entry.size, controlHeight = Theme.Metric.ControlBar.bar.height
        let library = PlayerGeometry.compactLibraryWidth(windowWidth: size.width, panelOpen: false)
        let area = PlayerGeometry.informationRect(in: size, top: Theme.Metric.Window.topBar.height, bottom: controlHeight,
                                                  leading: library, rightPanel: nil)
        let toast = Theme.Metric.Dialogs.resumeToast
        let y = Int(area.maxY - toast.height / 2)
        let accent = (Int(area.minX)..<Int(area.maxX)).filter { pixels.isAccent(x: $0, y: y) }
        XCTAssertFalse(accent.isEmpty, "the toast shows in the 480 pt window")
        // A truncated label fills all the room the toast leaves; "Continue" hugs its label.
        let room = area.width - toast.padding.leading - toast.padding.trailing - Theme.Spacing.gap10
            - Theme.Metric.Dialogs.resumeCloseButton.width
        XCTAssertLessThan(CGFloat(accent.count), room - Theme.Spacing.gap8, "the button hugs VLC's short label")
    }

    // MARK: D042/D053 PiP placeholder in Light

    func testLightPiPPlaceholderSitsOnTheDarkVideoBase() throws {
        let light = GalleryEnvironment(colorScheme: .light)
        let pip = try Pixels(GalleryRenderer.render(XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/pip")), scale: 1, environment: light))
        let shipping = try Pixels(GalleryRenderer.render(XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/shipping")),
                                                         scale: 1, environment: light))
        let surface = pip.color(x: 300, y: 400)
        XCTAssertLessThan(max(surface.0, surface.1, surface.2), 40, "the placeholder is the dark video background")
        // The bars over it read as over video, the same as over a playing clip (D053).
        for y in [Int(Theme.Metric.Window.topBar.height / 2), Int(Theme.Metric.Window.player.height - 4)] {
            XCTAssertTrue(pip.near(x: 1400, y: y, shipping.color(x: 1400, y: y), tolerance: 4), "bar at y \(y)")
        }
    }

    // MARK: D055 fullscreen strip

    func testStripTrackerFollowsTheStripWithoutNotifications() async throws {
        var inset = 0.0
        var reported: [Double] = []
        let tracker = MXRSystemStripTracker(sample: { inset }, report: { reported.append($0) })
        tracker.start(interval: 0.01)
        XCTAssertEqual(reported, [0], "the first sample reports at once")
        // AppKit slides the strip down and posts nothing: the timer still sees it.
        inset = 52
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reported, [0, 52])
        inset = 0
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(reported, [0, 52, 0], "each change is reported once")
        tracker.stop()
        XCTAssertFalse(tracker.isRunning)
        inset = 52
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(reported, [0, 52, 0], "nothing is sampled outside fullscreen")
    }
}

private struct Pixels {
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

    /// The orange accent fill (#D37918 / #E8851A).
    func isAccent(x: Int, y: Int) -> Bool {
        let (r, g, b) = color(x: x, y: y)
        return r > 180 && g > 90 && g < 160 && b < 70
    }

    /// A light glyph pixel on the dark bar.
    func isBright(x: Int, y: Int) -> Bool {
        let (r, g, b) = color(x: x, y: y)
        return r + g + b > 180 * 3 / 2 && abs(r - b) < 40
    }

    func near(x: Int, y: Int, _ expected: (Int, Int, Int), tolerance: Int) -> Bool {
        let actual = color(x: x, y: y)
        return abs(actual.0 - expected.0) <= tolerance && abs(actual.1 - expected.1) <= tolerance
            && abs(actual.2 - expected.2) <= tolerance
    }
}
