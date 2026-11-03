import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
@testable import MXRUI
import SwiftUI
import XCTest

/// Findings of the second live run on the installed window (live2/triage.json, A-window) and the
/// close wave's open window items.
@MainActor
final class WindowLiveRun2Tests: XCTestCase {
    // MARK: Minimum window size (live major)

    func testPlayerWindowKeepsItsMinimumForEveryResize() {
        _ = NSApplication.shared
        let minimum = MXRPlayerWindow.minimumContentSize
        XCTAssertEqual(minimum, CGSize(width: 480, height: 270))
        let host = NSHostingView(rootView: MXRAppView().appModel(AppModel.mock(.pausedEpisode)))
        let window = MXRPlayerWindow.make(contentRect: NSRect(x: 100, y: 100, width: 960, height: 540), contentView: host)
        defer { window.close() }
        // The hosting view rewrites the window's minimum from SwiftUI's (0 × 32) on every layout.
        settle(host, seconds: 0.1)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.width, minimum.width)
        XCTAssertGreaterThanOrEqual(window.contentMinSize.height, minimum.height)
        // Accessibility and AppleScript resize through setFrame, which AppKit does not constrain.
        let top = window.frame.maxY
        window.setFrame(NSRect(x: 100, y: 100, width: 300, height: 200), display: false)
        var content = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(content.width, minimum.width, accuracy: 0.5)
        XCTAssertEqual(content.height, minimum.height, accuracy: 0.5)
        XCTAssertEqual(window.frame.maxY, 300, accuracy: 0.5, "the top edge stays where it was asked for")
        window.setContentSize(NSSize(width: 201, height: 161))
        content = window.contentRect(forFrameRect: window.frame).size
        XCTAssertGreaterThanOrEqual(content.width, minimum.width)
        XCTAssertGreaterThanOrEqual(content.height, minimum.height)
        window.setFrame(NSRect(x: 0, y: 0, width: 1200, height: 700), display: false)
        XCTAssertEqual(window.frame.size, CGSize(width: 1200, height: 700), "larger frames are untouched")
        _ = top
    }

    // MARK: Hide UI moves the video in one step (live minor)

    func testHideUIRoundTripPutsTheVideoBackInOneStep() {
        let app = AppModel.mock(.pausedEpisode)
        let recorder = FrameRecorder()
        let host = hosting(app, size: CGSize(width: 960, height: 540), video: AnyView(RecorderView(view: recorder)))
        app.interface.toggleQueuePanel(.queue)
        settle(host)
        let shown = recorder.windowRect
        recorder.sizes.removeAll()
        app.interface.toggleUIHidden()
        settle(host)
        let hidden = recorder.windowRect
        XCTAssertEqual(hidden.size, CGSize(width: 940, height: 520), "Hide UI: the thin 10 pt frame")
        // Live run 2: the closing queue's animation carried the canvas through ~680 in-between sizes
        // (445.30 pt, 519.76 pt …), and the vout kept a stretched picture after the round trip.
        XCTAssertTrue(recorder.sizes.allSatisfy { $0 == hidden.size }, "the vout sees only the final size, not \(recorder.sizes.count) steps")
        recorder.sizes.removeAll()
        app.interface.toggleUIHidden()
        settle(host)
        XCTAssertTrue(recorder.sizes.allSatisfy { $0 == shown.size }, "\(recorder.sizes.count) steps back")
        XCTAssertEqual(recorder.windowRect, shown, "the video is back exactly where it was")
        XCTAssertEqual(app.interface.rightPanel, .queue(.queue))
    }

    // MARK: Right panels fade out (C4, D024)

    /// SwiftUI keeps a removed view on screen for its removal transition but keeps re-rendering it from
    /// the current state. The panels read `interface.rightPanel`, which is already nil then, so they
    /// drew nothing for the 0.1 s fade and vanished in one frame while menus and dialogs faded (C4).
    /// The panel layer draws the panel it was inserted with, whatever the model says now.
    func testTheRightPanelLayerDrawsItsPanelAfterTheModelClosedIt() throws {
        let app = AppModel.mock(.pausedEpisode)
        let size = Theme.Metric.SidePanels.tracksPopup
        let panels: [RightPanel] = [.tracks(.subtitles), .sidebar(.playback), .queue(.queue)]
        for panel in panels {
            app.interface.closeRightPanel()
            XCTAssertNil(app.interface.rightPanel)
            let host = NSHostingView(rootView: MXRRightPanelLayer(panel: panel).frame(width: size.width, height: size.height)
                .appModel(app))
            host.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            settle(host, seconds: 0.1)
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            var opaque = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 8) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { opaque += 1 }
            }
            XCTAssertGreaterThan(opaque, 100, "\(panel): the closing panel still draws while it fades out")
        }
    }

    func testClosingARightPanelLeavesNothingBehind() throws {
        let app = AppModel.mock(.pausedEpisode)
        let size = CGSize(width: 960, height: 540)
        let host = hosting(app, size: size, video: AnyView(Color(red: 1, green: 0, blue: 0)))
        settle(host)
        let frame = PlayerGeometry.rightPanelFrame(.queue(.queue), in: size, controlHeight: Theme.Metric.ControlBar.bar.height,
                                                   leadingInset: 0)
        let probe = CGPoint(x: frame.midX, y: frame.midY)
        let video = try color(host, at: probe)
        app.interface.toggleQueuePanel(.queue)
        settle(host)
        XCTAssertFalse(try color(host, at: probe).near(video), "the queue covers the video")
        app.interface.closeRightPanel()
        settle(host)
        XCTAssertTrue(try color(host, at: probe).near(video), "and is gone after its fade")
    }

    // MARK: Light and Dark place the picture identically (D055)

    func testLightAndDarkGiveTheVideoTheSameRect() {
        func rect(_ theme: ThemePreference, size: CGSize) -> CGRect {
            let app = AppModel.mock(.pausedEpisode)
            app.appearance.setTheme(theme)
            let recorder = FrameRecorder()
            let host = hosting(app, size: size, video: AnyView(RecorderView(view: recorder)))
            settle(host, seconds: 0.1)
            return recorder.windowRect
        }
        for size in [CGSize(width: 960, height: 540), CGSize(width: 1920, height: 1080), CGSize(width: 1200, height: 900)] {
            let dark = rect(.dark, size: size), light = rect(.light, size: size)
            XCTAssertEqual(light, dark, "\(size): live run 2 measured Light 1 pt higher and 20 pt wider")
            XCTAssertEqual(dark.minY, Theme.Metric.Window.topBar.height + Theme.Stroke.hairline, "Player-6: the picture starts at y 41")
        }
    }

    // MARK: Customize never puts the picture under the bars (live minor, H-design)

    func testCustomizeKeepsTheWholePictureBetweenTheBars() {
        let app = AppModel.mock(.pausedEpisode)
        let recorder = FrameRecorder()
        let size = CGSize(width: 960, height: 540)
        let host = hosting(app, size: size, video: AnyView(RecorderView(view: recorder)))
        settle(host, seconds: 0.1)
        app.layouts.beginEditing(profileID: app.profiles.currentID, kind: .video)
        app.interface.isCustomizing = true
        settle(host, seconds: 0.2)
        let rows = CGFloat(PlayerGeometry.controlRows(layoutRows: app.playerLayout.bottom.count, customizing: true))
        let picture = recorder.windowRect
        XCTAssertGreaterThanOrEqual(picture.minY, Theme.Metric.Window.topBar.height, "the burnt-in timecode stays visible")
        XCTAssertLessThanOrEqual(picture.maxY, size.height - rows * Theme.Metric.ControlBar.bar.height + 0.5)
    }

    // MARK: D057 library beside a panel

    func testHideUIKeepsTheLibraryThatYieldedToAPanel() {
        let interface = InterfaceModel()
        interface.library = .compact
        interface.toggleQueuePanel(.queue)
        interface.reconcileLibraryAndPanel(fit: false)
        XCTAssertTrue(interface.libraryYieldedToPanel)
        // ⌘\ twice; the window reconciles on every panel change, also those Hide UI makes.
        interface.toggleUIHidden()
        interface.reconcileLibraryAndPanel(fit: false)
        interface.toggleUIHidden()
        interface.reconcileLibraryAndPanel(fit: false)
        XCTAssertEqual(interface.rightPanel, .queue(.queue))
        XCTAssertEqual(interface.library, .hidden)
        interface.closeRightPanel()
        interface.reconcileLibraryAndPanel(fit: false)
        XCTAssertEqual(interface.library, .compact, "D057: the library comes back when the panel closes")
    }

    /// The window composition itself keeps the library and a panel apart: nothing here calls the model.
    func testTheWindowMakesTheLibraryYieldAndComeBackInANarrowWindow() {
        let app = AppModel.mock(.pausedEpisode)
        let host = hosting(app, size: MXRPlayerWindow.minimumContentSize, video: AnyView(Color.black))
        app.interface.library = .compact
        settle(host, seconds: 0.2)
        app.interface.toggleQueuePanel(.queue)
        settle(host, seconds: 0.2)
        XCTAssertEqual(app.interface.library, .hidden, "at 480 pt the library yields to the queue")
        XCTAssertTrue(app.interface.libraryYieldedToPanel)
        app.interface.closeRightPanel()
        settle(host, seconds: 0.2)
        XCTAssertEqual(app.interface.library, .compact, "and comes back when it closes")
        app.interface.toggleSidebar(.playback)
        settle(host, seconds: 0.2)
        app.interface.library = .hidden
        settle(host, seconds: 0.2)
        app.interface.library = .compact
        settle(host, seconds: 0.2)
        XCTAssertNil(app.interface.rightPanel, "opening the library closes the panel")
        // Growing the window lets both stay.
        app.interface.toggleQueuePanel(.queue)
        settle(host, seconds: 0.2)
        host.window?.setContentSize(NSSize(width: 1200, height: 700))
        settle(host, seconds: 0.2)
        XCTAssertEqual(app.interface.library, .compact, "the yielded library returns once both fit")
        XCTAssertEqual(app.interface.rightPanel, .queue(.queue))
    }

    // MARK: Resume toast hover (14m09.8)

    func testContinueButtonDarkensUnderThePointer() {
        XCTAssertEqual(ContinueButtonStyle.fill(pressed: false, hovered: false), Theme.Color.accentMain)
        XCTAssertEqual(ContinueButtonStyle.fill(pressed: false, hovered: true), Theme.Color.accentDim,
                       "14m09.8 shows the button darkened under the cursor")
        XCTAssertEqual(ContinueButtonStyle.fill(pressed: true, hovered: true), Theme.Color.accentDim)
    }

    // MARK: Helpers

    private var windows: [NSWindow] = []

    private func hosting(_ app: AppModel, size: CGSize, video: AnyView) -> NSHostingView<AnyView> {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: AnyView(MXRAppView(videoView: video).appModel(app)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        windows.append(window)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private func color(_ view: NSView, at point: CGPoint) throws -> RGB {
        view.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let color = try XCTUnwrap(rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB))
        return RGB(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
    }

    struct RGB {
        let r, g, b: CGFloat
        func near(_ other: RGB) -> Bool { abs(r - other.r) < 0.03 && abs(g - other.g) < 0.03 && abs(b - other.b) < 0.03 }
    }

    private func settle(_ view: NSView, seconds: TimeInterval = 0.4) {
        for _ in 0..<Int(seconds / 0.02) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            view.layoutSubtreeIfNeeded()
        }
    }
}

/// Records every size SwiftUI gives the video view, as the vout surface sees them.
final class FrameRecorder: NSView {
    var sizes: [CGSize] = []
    /// The view's rect in window-content coordinates, y down from the top bar.
    var windowRect: CGRect {
        guard let content = window?.contentView else { return frame }
        let rect = convert(bounds, to: content)
        return content.isFlipped ? rect : CGRect(x: rect.minX, y: content.bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sizes.append(newSize)
    }
}

private struct RecorderView: NSViewRepresentable {
    let view: FrameRecorder
    func makeNSView(context: Context) -> FrameRecorder { view }
    func updateNSView(_ nsView: FrameRecorder, context: Context) {}
}
