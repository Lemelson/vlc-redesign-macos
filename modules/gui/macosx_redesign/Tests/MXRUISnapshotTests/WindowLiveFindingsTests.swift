import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Findings of the first live run on the installed window (live-run-1-window.json): the fullscreen
/// top-edge reveal, the Light canvas, tooltips of hidden bars, Hide UI and the subtitle inset.
@MainActor
final class WindowLiveFindingsTests: XCTestCase {
    // MARK: (1) Fullscreen top edge (D055)

    func testMacOSFullscreenStripRevealsTheTopBarBelowItAndItStaysReachable() async throws {
        let mock = MockBackend(scenario: .playingEpisode)
        mock.settings.setValue(.float(0), for: "macosx-redesign-autohide-delay", apply: .nextMedia)
        let app = mock.makeAppModel(clockTicks: false)
        app.player.setFullscreen(true)
        app.player.play()
        let reveal = PlayerChromeReveal()
        let size = Theme.Metric.Window.player.size
        reveal.pointer(at: CGPoint(x: 960, y: 540), in: size, controlHeight: 54, app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(app.interface.isTopBarVisible)
        // The pointer touches the top edge: macOS slides its strip over the window and the window
        // loses the pointer. Before D055 nothing else happened and the empty strip was all one saw.
        reveal.pointer(at: nil, in: size, controlHeight: 54, app: app)
        app.interface.fullscreenSystemInset = 52
        reveal.evaluate(app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(app.interface.isTopBarVisible, "the app's top bar comes with macOS's strip")
        XCTAssertEqual(app.interface.topBarOffset, 52, "drawn below the strip, not under it")
        // The strip slides away as the pointer comes down into the bar: the bar keeps its place.
        app.interface.fullscreenSystemInset = 0
        reveal.pointer(at: CGPoint(x: 960, y: 52 + 20), in: size, controlHeight: 54, app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(app.interface.isTopBarVisible, "the pointer over the moved bar keeps it")
        XCTAssertEqual(app.interface.topBarOffset, 52)
        // Leaving it hides the bar, which then returns to the top edge.
        reveal.pointer(at: CGPoint(x: 960, y: 540), in: size, controlHeight: 54, app: app)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(app.interface.isTopBarVisible)
        XCTAssertEqual(app.interface.topBarOffset, 0)
        reveal.cancel()
    }

    func testSystemStripInsetFollowsTheStripWindowFrame() {
        let window = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        // Hidden: AppKit parks the strip above the screen.
        XCTAssertEqual(MXRWindowControls.fullscreenSystemInset(stripFrame: CGRect(x: 0, y: 1117, width: 1728, height: 40),
                                                               windowFrame: window, stripShown: true), 0)
        // Shown below a 24 pt menu bar: 24 + 28 pt from the window's top.
        XCTAssertEqual(MXRWindowControls.fullscreenSystemInset(stripFrame: CGRect(x: 0, y: 1117 - 52, width: 1728, height: 28),
                                                               windowFrame: window, stripShown: true), 52)
        XCTAssertEqual(MXRWindowControls.fullscreenSystemInset(stripFrame: CGRect(x: 0, y: 1117 - 52, width: 1728, height: 28),
                                                               windowFrame: window, stripShown: false), 0)
    }

    func testAWindowNeverOffsetsItsTopBar() {
        let app = AppModel.mock(.playingEpisode)
        app.interface.fullscreenSystemInset = 40
        let reveal = PlayerChromeReveal()
        reveal.evaluate(app: app)
        XCTAssertEqual(app.interface.topBarOffset, 0, "the inset applies only in fullscreen")
        reveal.cancel()
    }

    // MARK: (2) Light keeps the picture where Dark has it (D055)

    func testLightKeepsThePictureBetweenThePinnedBars() throws {
        let size = CGSize(width: 960, height: 540)
        let pixels = try render(theme: .light, size: size) { $0.interface.library = .compact }
        let bar = Int(Theme.Metric.ControlBar.bar.height)
        // Just above the control bar the picture shows; under the bars there is only the canvas.
        XCTAssertTrue(pixels.isRed(x: 700, y: Int(size.height) - bar - 6), "picture above the control bar")
        // The translucent bars show the canvas, not the picture: another video leaves them unchanged.
        let blue = try render(theme: .light, size: size, video: Color(red: 0, green: 0, blue: 1)) { $0.interface.library = .compact }
        for y in [Int(size.height) - bar / 2, Int(Theme.Metric.Window.topBar.height) / 2] {
            XCTAssertTrue(pixels.same(as: blue, x: 700, y: y), "no picture under the bar at y \(y)")
        }
        XCTAssertTrue(pixels.isRed(x: 700, y: Int(Theme.Metric.Window.topBar.height) + 4), "picture right below the top bar")
    }

    // MARK: (3) A hidden bar leaves the tree (tooltip stayed after auto-hide)

    func testHiddenBarsLeaveTheViewTree() throws {
        let mock = MockBackend(scenario: .playingEpisode)
        mock.settings.setValue(.string("always"), for: "macosx-redesign-autohide", apply: .nextMedia)
        let app = mock.makeAppModel(clockTicks: false)
        app.player.play()
        app.interface.areBarsVisible = true
        let host = hosting(app, size: CGSize(width: 960, height: 540))
        // The window background and the top bar each host a drag region (D022).
        XCTAssertEqual(dragAreas(in: host), 2)
        app.interface.areBarsVisible = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(dragAreas(in: host), 1, "the hidden top bar keeps no views, so no tooltip can outlive it")
    }

    // MARK: (4) Hide UI gives the panel back

    func testTurningHideUIOffReopensThePanelThatWasOpen() {
        let ui = InterfaceModel()
        ui.toggleQueuePanel(.queue)
        ui.isAppMenuOpen = true
        ui.toggleUIHidden()
        XCTAssertNil(ui.rightPanel)
        ui.toggleUIHidden()
        XCTAssertEqual(ui.rightPanel, .queue(.queue), "the queue comes back with the UI")
        XCTAssertFalse(ui.isAppMenuOpen, "the transient ⋯ menu stays closed")
        ui.closeRightPanel()
        ui.toggleUIHidden(); ui.toggleUIHidden()
        XCTAssertNil(ui.rightPanel, "nothing was open, nothing opens")
    }

    // MARK: (6) Subtitles above the fullscreen control bar

    func testRevealedFullscreenControlBarReportsTheSubtitleInset() throws {
        let app = AppModel.mock(.playingEpisode)
        app.player.setFullscreen(true)
        let host = hosting(app, size: CGSize(width: 960, height: 540))
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(app.interface.subtitleSafeInset, Double(Theme.Metric.ControlBar.bar.height), accuracy: 0.5)
        app.player.setFullscreen(false)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(app.interface.subtitleSafeInset, 0, "between pinned bars nothing covers the picture")
    }

    // MARK: Helpers

    private func hosting(_ app: AppModel, size: CGSize, video: Color = Color(red: 1, green: 0, blue: 0),
                         configure: (AppModel) -> Void = { _ in }) -> NSHostingView<AnyView> {
        _ = NSApplication.shared
        configure(app)
        let view = NSHostingView(rootView: AnyView(MXRAppView(videoView: AnyView(video))
            .appModel(app)))
        view.frame = CGRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func render(theme: ThemePreference, size: CGSize, video: Color = Color(red: 1, green: 0, blue: 0),
                        configure: (AppModel) -> Void) throws -> Pixels {
        let app = AppModel.mock(.pausedEpisode)
        app.appearance.setTheme(theme)
        let view = hosting(app, size: size, video: video, configure: configure)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return Pixels(rep: rep, scale: CGFloat(rep.pixelsWide) / size.width)
    }

    private func dragAreas(in view: NSView) -> Int {
        (view is MXRWindowDragArea.DragView ? 1 : 0) + view.subviews.reduce(0) { $0 + dragAreas(in: $1) }
    }

    private struct Pixels {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        func isRed(x: Int, y: Int) -> Bool {
            guard let color = rep.colorAt(x: Int(CGFloat(x) * scale), y: Int(CGFloat(y) * scale))?.usingColorSpace(.sRGB) else { return false }
            return color.redComponent > 0.8 && color.greenComponent < 0.25 && color.blueComponent < 0.25
        }
        func same(as other: Pixels, x: Int, y: Int) -> Bool {
            let px = Int(CGFloat(x) * scale), py = Int(CGFloat(y) * scale)
            guard let a = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB),
                  let b = other.rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { return false }
            return abs(a.redComponent - b.redComponent) < 0.02 && abs(a.blueComponent - b.blueComponent) < 0.02
        }
    }
}
