import AppKit
import MXRCore
import MXRDesign
@testable import MXRGalleryCatalog
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// D021–D024, D029, D030: the shipping window composition.
@MainActor
final class WindowCompositionTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            GalleryRenderer.matchFigmaTextRasterization()
            GalleryCatalog.bootstrap()
        }
    }

    // MARK: Geometry

    func testCanvasDependsOnWindowModeOnly() {
        // Player-6: the dark window frames the video between pinned bars (6586:17371 at y 41).
        let framed = PlayerCanvasStyle.resolve(fullscreen: false, uiHidden: false, customizing: false, light: false, autoHidesInWindow: false)
        XCTAssertEqual(framed, .framed)
        let insets = framed.insets(controlHeight: Theme.Metric.ControlBar.bar.height)
        XCTAssertEqual(insets.top, 41)
        XCTAssertEqual(insets.leading, 10)
        XCTAssertEqual(insets.trailing, 10)
        XCTAssertEqual(insets.bottom, Theme.Metric.ControlBar.bar.height)
        XCTAssertEqual(framed.cornerRadius, 9)
        // Hide UI and the always-auto-hidden window: the thin 10 pt frame (3328:11554, 03m53.6).
        for style in [PlayerCanvasStyle.resolve(fullscreen: false, uiHidden: true, customizing: false, light: false, autoHidesInWindow: false),
                      .resolve(fullscreen: false, uiHidden: false, customizing: false, light: false, autoHidesInWindow: true)] {
            XCTAssertEqual(style, .thinFrame)
            XCTAssertEqual(style.insets(controlHeight: 54).top, 10)
            XCTAssertEqual(style.insets(controlHeight: 54).bottom, 10)
        }
        // Fullscreen has no frame (§03); Customize draws the video under the bars; Light runs the canvas under them (D055).
        XCTAssertEqual(PlayerCanvasStyle.resolve(fullscreen: true, uiHidden: true, customizing: false, light: false, autoHidesInWindow: false), .fullBleed)
        XCTAssertEqual(PlayerCanvasStyle.resolve(fullscreen: false, uiHidden: false, customizing: false, light: true, autoHidesInWindow: false), .underBars)
        XCTAssertEqual(PlayerCanvasStyle.resolve(fullscreen: false, uiHidden: false, customizing: true, light: false, autoHidesInWindow: false), .fullBleed)
        XCTAssertEqual(PlayerCanvasStyle.fullBleed.insets(controlHeight: 54).top, 0)
    }

    func testRightPanelsShareTheFigmaSlotBetweenTheBars() {
        let window = Theme.Metric.Window.player.size
        // Controls 491:2216: popup 491:2243, 400×524 at (1500, 1026 - 544).
        let tracks = PlayerGeometry.rightPanelFrame(.tracks(.subtitles), in: window, controlHeight: 54, leadingInset: 0)
        XCTAssertEqual(tracks, CGRect(x: 1500, y: 482, width: 400, height: 524))
        // Controls 2238:9432 / 491:1781: sidebar and queue 400×946 at (1500, 1026 - 966).
        for panel in [RightPanel.sidebar(.subtitles), .queue(.queue)] {
            XCTAssertEqual(PlayerGeometry.rightPanelFrame(panel, in: window, controlHeight: 54, leadingInset: 0),
                           CGRect(x: 1500, y: 60, width: 400, height: 946))
        }
        // Small windows: the popover stays anchored above the bar and never covers the top bar.
        let small = PlayerGeometry.rightPanelFrame(.tracks(.audio), in: CGSize(width: 480, height: 270), controlHeight: 54, leadingInset: 0)
        XCTAssertEqual(small.maxY, 270 - 54 - 20)
        XCTAssertEqual(small.maxX, 480 - 20)
        XCTAssertGreaterThanOrEqual(small.minY, 40 + 20)
        // Two control rows push the anchor up with the bar.
        XCTAssertEqual(PlayerGeometry.rightPanelFrame(.tracks(.audio), in: window, controlHeight: 108, leadingInset: 0).maxY, 1080 - 108 - 20)
    }

    // MARK: Popups and bars

    func testEscAndOutsideClickCloseTheFrontMostPopupOnly() {
        let ui = InterfaceModel()
        XCTAssertFalse(ui.dismissTransientPopup(), "nothing open: the event belongs to playback")
        ui.toggleTracks(.audio)
        ui.isAppMenuOpen = true
        XCTAssertTrue(ui.hasTransientPopup)
        XCTAssertTrue(ui.dismissTransientPopup())
        XCTAssertFalse(ui.isAppMenuOpen)
        XCTAssertEqual(ui.rightPanel, .tracks(.audio))
        XCTAssertTrue(ui.dismissTransientPopup())
        XCTAssertNil(ui.rightPanel)
        ui.toggleSidebar(.playback)
        ui.toggleUIHidden()
        XCTAssertNil(ui.rightPanel, "Hide UI removes all chrome, popups included")
    }

    func testBarsRevealIndependentlyAndHideAfterTheDelay() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        mock.settings.setValue(.float(0), for: "macosx-redesign-autohide-delay", apply: .nextMedia)
        let app = mock.makeAppModel(clockTicks: false)
        app.player.setFullscreen(true)
        app.player.play()
        XCTAssertTrue(app.shouldAutoHideControls)
        let reveal = PlayerChromeReveal()
        let size = Theme.Metric.Window.player.size
        reveal.pointer(at: CGPoint(x: 960, y: 10), in: size, controlHeight: 54, app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(app.interface.isTopBarVisible, "03m51.0: the pointer near the top reveals the top bar")
        XCTAssertFalse(app.interface.isControlBarVisible, "…and only the top bar")
        reveal.pointer(at: CGPoint(x: 960, y: 1075), in: size, controlHeight: 54, app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(app.interface.isTopBarVisible)
        XCTAssertTrue(app.interface.isControlBarVisible, "03m53.0: the pointer near the bottom reveals the control bar only")
        // A panel pins the control bar; the app menu pins the top bar.
        app.interface.toggleTracks(.subtitles)
        app.interface.isAppMenuOpen = true
        reveal.pointer(at: CGPoint(x: 960, y: 540), in: size, controlHeight: 54, app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(app.interface.isTopBarVisible)
        XCTAssertTrue(app.interface.isControlBarVisible)
        app.interface.dismissTransientPopup(); app.interface.dismissTransientPopup()
        reveal.evaluate(app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(app.interface.isTopBarVisible)
        XCTAssertFalse(app.interface.isControlBarVisible)
        // Paused playback keeps both bars.
        app.player.pause()
        reveal.evaluate(app: app)
        XCTAssertTrue(app.interface.isTopBarVisible && app.interface.isControlBarVisible)
        reveal.cancel()
    }

    func testLaunchLibraryFollowsStartInCompactMode() {
        let ui = InterfaceModel()
        ui.presentLaunchLibrary(compact: false)
        XCTAssertEqual(ui.library, .full, "D029: launch opens the full-window library on Home")
        ui.library = .hidden
        ui.presentLaunchLibrary(compact: true)
        XCTAssertEqual(ui.library, .compact)
    }

    func testPlayWithAnEmptyQueueOpensTheLibraryInsteadOfFailing() {
        let app = MockBackend(scenario: .idle).makeAppModel(clockTicks: false)
        XCTAssertTrue(app.player.media == nil && app.queue.items.isEmpty)
        app.interface.library = .hidden
        app.perform(.playPause)
        XCTAssertEqual(app.interface.library, .full, "D029: Play with nothing queued opens Home")
        XCTAssertNil(app.player.errorMessage)
    }

    // MARK: Shipping composition renders (D030)

    func testShippingWindowPutsOneTopBarAtTheTopAndTheVideoInFrame312() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/shipping"))
        let image = try GalleryRenderer.render(entry, scale: 1)
        let pixels = try Pixels(image)
        // One 40 pt row: the title-bar colour from y 0 to 39 in the middle of the bar (no titlebar strip).
        let bar = Theme.Color.bgA3.value(scheme: .dark, accent: .orange)
        for y in [2, 20, 38] { XCTAssertTrue(pixels.matches(x: 700, y: y, bar), "top bar at y \(y)") }
        // Frame 312: the video starts 1 pt under the bar and 10 pt from the left edge.
        XCTAssertTrue(pixels.matches(x: 5, y: 300, bar), "10 pt left frame")
        XCTAssertFalse(pixels.matches(x: 15, y: 300, bar), "video inside the frame")
        // The cone follows the traffic lights with the group gap (D022).
        let reserve = ShippingWindowControls.measured.reserve
        XCTAssertGreaterThan(reserve, 0)
        XCTAssertLessThan(reserve, Double(Theme.Metric.Window.topBarLeftGroup.width))
    }

    func testShippingTrackPopoverIsAnchoredAboveTheControlBar() throws {
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S14.Window/subtitle-tracks"))
        let image = try GalleryRenderer.render(entry, scale: 1)
        let pixels = try Pixels(image)
        let video = pixels.color(x: 1700, y: 300)
        // The card covers the bottom-right slot (y 482–1006) and the video shows above it.
        XCTAssertFalse(pixels.matches(x: 1700, y: 990, video), "card bottom sits 20 pt above the bar")
        XCTAssertTrue(pixels.matches(x: 1700, y: 470, video), "nothing floats mid-right above the card")
    }

    func testPanelCommandsAreOffOverTheFullLibrary() {
        // A-13: the right panels do not exist over the full library, so their commands must not look enabled.
        let app = MockBackend(scenario: .pausedEpisode).makeAppModel(clockTicks: false)
        let commands: [AppCommand] = [.toggleQueue, .toggleSettingsSidebar, .showSubtitleTracks, .showAudioTracks]
        app.interface.library = .full
        for command in commands { XCTAssertFalse(app.canPerform(command), "\(command) over the full library") }
        app.interface.library = .compact
        for command in commands { XCTAssertTrue(app.canPerform(command), "\(command) over the player") }
        app.perform(.showSubtitleTracks)
        XCTAssertEqual(app.interface.rightPanel, .tracks(.subtitles))
    }

    // MARK: Top bar content (A-01, A-07)

    func testFolderChipStaysForMediaOutsideTheLibrary() throws {
        // 12-continue-watching 14m09.8: DON'T BLINK (no library folder) shows the "Videos" chip.
        XCTAssertEqual(MXRControlTitles.folderChip(folder: nil, audioOnly: false), "Videos")
        XCTAssertEqual(MXRControlTitles.folderChip(folder: nil, audioOnly: true), "Songs")
        XCTAssertEqual(MXRControlTitles.folderChip(folder: FolderReference(id: "f", name: "S01"), audioOnly: false), "S01")
        // The default row keeps the divider followed by the chip (no dangling divider).
        let controls = PlayerGeometry.topItems(PlayerLayout.video.top, fullLibrary: false).map(\.control)
        let divider = try XCTUnwrap(controls.firstIndex(of: .divider))
        XCTAssertEqual(controls[divider + 1], .folderName)
        // In the shipping window (Player-6 media: a file outside the library) the chip is drawn after the divider.
        let entry = try XCTUnwrap(GalleryCatalog.entry(id: "S01.Window/shipping"))
        let mock = MockBackend(scenario: .pausedEpisode)
        ShippingGallery.figmaPlayer6(mock)
        XCTAssertNotNil(mock.player.currentMedia)
        XCTAssertNil(mock.player.currentMedia?.folder)
        let pixels = try Pixels(GalleryRenderer.render(entry, scale: 1))
        let bar = Theme.Color.bgA3.value(scheme: .dark, accent: .orange)
        let drawn = (150...215).filter { x in (12...28).contains { y in !pixels.matches(x: x, y: y, bar, tolerance: 24) } }
        XCTAssertGreaterThan(drawn.count, 20, "folder icon and \"Videos\" after the divider")
    }

    func testNarrowTopBarHidesTheTitleInsteadOfAnEllipsis() {
        // 480 pt shipping window (S01.Player/compact): reserve, cone, menu, toggle, divider, chip | spacer title spacer | fullscreen.
        let width: CGFloat = 480 - Theme.Metric.Window.topBar.padding.leading - Theme.Metric.Window.topBar.padding.trailing
        let gaps: [CGFloat] = [0, 7, 7, 10, 0, 0, 7, 7, 7, 7]
        let longFolder: CGFloat = 600, title: CGFloat = 220
        let widths: [CGFloat] = [62, 24, 28, 28, 24, longFolder, 0, title, 0, 28]
        let result = PlayerGeometry.headerWidths(widths, gaps: gaps, title: 7, folders: [5], flexible: [6, 8], width: width)
        XCTAssertEqual(result.title, 0, "no room for a readable title: hidden, never a lone ellipsis")
        // PlayerRowLayout places the title centred, outside the running x, so its own gap takes no room.
        let placedGaps = gaps.enumerated().filter { $0.offset != 7 }.reduce(CGFloat.zero) { $0 + $1.element }
        XCTAssertLessThanOrEqual(result.items.reduce(0, +) + placedGaps, width, "the row fits")
        XCTAssertGreaterThan(result.items[5], 100, "the folder gets the room the title left")
        // A wider window first truncates the folder so the title keeps at least its minimum.
        let wide = PlayerGeometry.headerWidths(widths, gaps: gaps, title: 7, folders: [5], flexible: [6, 8], width: 900)
        let titleWidth = wide.title ?? 0
        XCTAssertGreaterThanOrEqual(titleWidth, MXRPlayerMetrics.headerTitleMinWidth)
        XCTAssertLessThan(wide.items[5], longFolder)
        let leading = (0..<7).reduce(CGFloat.zero) { $0 + wide.items[$1] + gaps[$1] }
        XCTAssertLessThanOrEqual(2 * leading + titleWidth, 900 + 0.5, "the centred title clears the left group")
        // Figma width: nothing shrinks.
        let figma = PlayerGeometry.headerWidths(widths.enumerated().map { $0.offset == 5 ? 82 : $0.element }, gaps: gaps,
                                                title: 7, folders: [5], flexible: [6, 8], width: 1888)
        XCTAssertEqual(figma.title, title)
        XCTAssertEqual(figma.items[5], 82)
    }

    // MARK: Player information placement (A-02, A-08)

    func testOSDAndToastStayInTheVisibleVideo() {
        let window = Theme.Metric.Window.player.size
        let queue = PlayerGeometry.rightPanelFrame(.queue(.queue), in: window, controlHeight: 54, leadingInset: 0)
        let area = PlayerGeometry.informationRect(in: window, top: 40, bottom: 54, leading: 0, rightPanel: queue)
        XCTAssertFalse(area.intersects(queue), "the OSD and toast never draw over an open queue or sidebar")
        XCTAssertEqual(area.maxX, queue.minX - Theme.Metric.panelInset)
        XCTAssertEqual(area.minY, 40 + Theme.Metric.panelInset, "D027: top-right, under the top bar")
        // 480 pt with the compact library: inside the video, inset from both sides.
        let small = CGSize(width: 480, height: 270)
        let library = small.width * MXRPlayerMetrics.compactLibraryShare
        let narrow = PlayerGeometry.informationRect(in: small, top: 40, bottom: 54, leading: library, rightPanel: nil)
        XCTAssertEqual(narrow.minX, library + Theme.Metric.panelInset)
        XCTAssertEqual(narrow.maxX, small.width - Theme.Metric.panelInset)
        // Hide UI: the whole window minus the inset.
        XCTAssertEqual(PlayerGeometry.informationRect(in: window, top: 0, bottom: 0, leading: 0, rightPanel: nil),
                       CGRect(origin: .zero, size: window).insetBy(dx: Theme.Metric.panelInset, dy: Theme.Metric.panelInset))
    }
}

/// Reads sRGB pixels of a render (origin top left).
private struct Pixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    func color(x: Int, y: Int) -> (Int, Int, Int) {
        let index = (y * width + x) * 4
        return (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]))
    }

    func matches(x: Int, y: Int, _ rgba: Theme.RGBA, tolerance: Int = 3) -> Bool {
        matches(x: x, y: y, (Int((rgba.red * 255).rounded()), Int((rgba.green * 255).rounded()), Int((rgba.blue * 255).rounded())), tolerance: tolerance)
    }

    func matches(x: Int, y: Int, _ expected: (Int, Int, Int), tolerance: Int = 3) -> Bool {
        let actual = color(x: x, y: y)
        return abs(actual.0 - expected.0) <= tolerance && abs(actual.1 - expected.1) <= tolerance && abs(actual.2 - expected.2) <= tolerance
    }
}
