import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

/// The window that ships (D030, ARC-01, M4): `MXRAppView` configured exactly as `MXRAppController`
/// does (PiP action, product defaults, content under the titlebar), framed by the native traffic
/// lights at the positions AppKit gives them in the same titled, full-size-content window with the
/// compact unified toolbar. These are the entries to compare with Player-6, Player - hide UI and
/// Player - Light. Only the media fixture and the UI state (panel, theme, Hide UI) are set per scene.
final class ShippingGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        [
            window("S01.Window/shipping", title: "Shipping window", scenario: .pausedEpisode,
                   node: Theme.Metric.Window.player.node, screens: ["S01", "S02", "S03", "S04"], media: figmaPlayer6,
                   deviations: [.differs(node: "I491:1928;1908:7389", outset: 14, decision: "D048",
                                         "head at the labelled 00:02:10; Figma draws it at 00:01:53"),
                                ] + macTopBar(leftGroup: "247:448", minimize: "247:466", maximize: "247:467", fullscreen: "247:468")),
            window("S06.Window/hidden-ui", title: "Shipping window · Hide UI", scenario: .pausedEpisode,
                   node: "3328:11554", screens: ["S06"]) { $0.interface.toggleUIHidden() },
            window("S72.Window/light", title: "Shipping window · Light with compact library", scenario: .playingEpisode,
                   node: "2425:13624", screens: ["S72", "S28"], light: true,
                   notes: "D053: the pinned Light bars are BG/A3 Transparent over the frame's #2D2B29 video base, Figma's #ABABAA (D043 superseded). D032/D044: watched rows are dimmed and the playing row is the accent, as in 11m57.",
                   configure: { app in
                       app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                       app.interface.library = .compact
                   }, media: figmaPlayerLight,
                   deviations: [.differs(node: "I2425:13645;1908:7389", outset: 14, decision: "D048",
                                         "head at the labelled 00:02:10; Figma draws it at 00:01:53"),
                                .differs(node: "I2425:13645;3603:12304", decision: "D049",
                                         "Light accent fills use Light/Accent/Main; the frame's play button keeps Dark/Accent/Main"),
                                ] + macTopBar(leftGroup: "2425:13627", minimize: "2425:13641", maximize: "2425:13642", fullscreen: "2425:13643")),
            window("S05.Window/top-reveal", title: "Shipping window · always auto-hide, pointer near the top",
                   scenario: .playingEpisode, screens: ["S05"], autoHide: true) { app in
                app.interface.isTopBarVisible = true; app.interface.isControlBarVisible = false
            },
            window("S05.Window/bottom-reveal", title: "Shipping window · always auto-hide, pointer near the bottom",
                   scenario: .playingEpisode, screens: ["S05"], autoHide: true) { app in
                app.interface.isTopBarVisible = false; app.interface.isControlBarVisible = true
            },
            window("S05.Window/thin-frame", title: "Shipping window · always auto-hide, bars hidden",
                   scenario: .playingEpisode, screens: ["S05", "S06"], autoHide: true) { app in
                app.interface.areBarsVisible = false
            },
            window("S14.Window/subtitle-tracks", title: "Shipping window · subtitle tracks", scenario: .pausedEpisode,
                   screens: ["S14"]) { $0.interface.toggleTracks(.subtitles) },
            window("S20.Window/subtitle-settings", title: "Shipping window · subtitle preferences", scenario: .pausedEpisode,
                   screens: ["S20"]) { $0.interface.toggleSidebar(.subtitles) },
            window("S22.Window/queue", title: "Shipping window · queue", scenario: .pausedEpisode,
                   screens: ["S22"]) { $0.interface.toggleQueuePanel(.queue) },
            window("S28.Window/compact-queue", title: "Shipping window · compact library and queue", scenario: .pausedEpisode,
                   screens: ["S28", "S22"]) { app in
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                app.interface.library = .compact
                app.interface.toggleQueuePanel(.queue)
            },
            window("S28.Window/compact-queue-minimum", title: "Shipping window · compact library and queue at the 480 pt minimum",
                   scenario: .pausedEpisode, screens: ["S28", "S22", "S27"],
                   notes: "D057: too narrow for the library at its minimum beside the 400 pt queue, so the library yields to the queue and returns when it closes.",
                   size: CGSize(width: Theme.Metric.Window.player.width / 4, height: Theme.Metric.Window.player.height / 4)) { app in
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                app.interface.library = .compact
                app.interface.toggleQueuePanel(.queue)
                // What the window's first layout pass does at this width (MXRAppView), before the capture.
                app.interface.reconcileLibraryAndPanel(fit: false)
            },
            window("S28.Window/compact-queue-narrow", title: "Shipping window · compact library and queue at 800 pt",
                   scenario: .pausedEpisode, screens: ["S28", "S22", "S27"],
                   notes: "D057: wide enough for both; the library keeps at least its 208 pt minimum and the queue its 400 pt.",
                   size: CGSize(width: Theme.Metric.Window.player.width / 2.4, height: Theme.Metric.Window.player.height / 2.4)) { app in
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                app.interface.library = .compact
                app.interface.toggleQueuePanel(.queue)
            },
            window("S66.Window/customization", title: "Shipping window · Customize Player", scenario: .pausedEpisode,
                   screens: ["S66"]) { $0.beginCustomizing() },
            // S67 (19m27.6): the saved alternate layout outside Customize — a full-width seek row
            // above centred transport, the top bar reduced to the cone and the window controls.
            window("S67.Window/two-row", title: "Shipping window · saved two-row layout", scenario: .pausedEpisode,
                   screens: ["S67"], configure: { app in
                app.layouts.beginEditing(profileID: app.profiles.currentID, kind: app.layoutKind)
                app.layouts.updateDraft { $0 = .twoRowExample }
                app.layouts.commit()
            }, media: figmaCustomize7),
            window("S05.Window/fullscreen", title: "Shipping window · fullscreen with both bars", scenario: .pausedEpisode,
                   screens: ["S05"],
                   notes: "Fullscreen composition in the titled host: the video fills the screen and the bars overlay it; the traffic lights are hidden because macOS shows them only in its own fullscreen titlebar with the menu bar. The menu-bar reveal and notch safe area need the live window.") { app in
                app.player.setFullscreen(true)
            },
            // D055: the pointer at the top edge brings macOS's menu bar and titlebar strip (not drawn
            // here: a 24 pt menu bar and the 28 pt titlebar with the traffic lights); the top bar shows
            // right below them.
            window("S05.Window/fullscreen-menubar", title: "Shipping window · fullscreen, menu bar revealed", scenario: .playingEpisode,
                   screens: ["S05"],
                   notes: "D055: macOS's fullscreen strip (menu bar and titlebar, its own window) covers the top 52 pt here and is not drawn offscreen; the app's top bar sits below it, the video stays where it was.") { app in
                app.player.setFullscreen(true)
                app.interface.fullscreenSystemInset = 52
                app.interface.topBarOffset = 52 // what the reveal controller sets on its first pass
            },
            window("S13.Window/osd-queue", title: "Shipping window · OSD with the queue open", scenario: .pausedEpisode,
                   screens: ["S13", "S22"]) { app in
                app.interface.toggleQueuePanel(.queue)
                app.osd.show("Crop: 2.35:1", pressedKey: "C")
            },
            window("S12.Window/continue-watching", title: "Shipping window · resume toast", scenario: .continueWatching,
                   screens: ["S12"]),
            window("S12.Window/continue-narrow", title: "Shipping window · resume toast at 640 pt with the compact library",
                   scenario: .continueWatching, screens: ["S12", "S27"],
                   size: CGSize(width: Theme.Metric.Window.player.width / 3, height: Theme.Metric.Window.player.height / 3)) { app in
                app.interface.library = .compact
            },
            window("S12.Window/continue-minimum", title: "Shipping window · resume toast at the 480 pt minimum with the compact library",
                   scenario: .continueWatching, screens: ["S12", "S27"],
                   notes: "D051: the video area is narrower than the actions-only toast, so the Continue button truncates.",
                   size: CGSize(width: Theme.Metric.Window.player.width / 4, height: Theme.Metric.Window.player.height / 4)) { app in
                app.interface.library = .compact
            },
            window("S01.Window/narrow", title: "Shipping window at 480 pt", scenario: .pausedEpisode, screens: ["S01"],
                   size: CGSize(width: Theme.Metric.Window.player.width / 4, height: Theme.Metric.Window.player.height / 4)),
            window("S01.Window/pip", title: "Shipping window · video in Picture in Picture", scenario: .playingEpisode,
                   screens: ["S01"]) { $0.player.setPictureInPicture(true) },
            window("S43.Window/launch", title: "Shipping window · launch with nothing to resume", scenario: .idle,
                   screens: ["S43"]) { app in
                app.library.select(.home)
                app.interface.presentLaunchLibrary(compact: app.startsInCompactMode)
            },
        ]
    }

    @MainActor
    private static func window(_ id: String, title: String, scenario: MockBackend.Scenario, node: String? = nil,
                               screens: [String], light: Bool = false, autoHide: Bool = false,
                               notes: String? = nil, size: CGSize = Theme.Metric.Window.player.size,
                               configure: @escaping @MainActor (AppModel) -> Void = { _ in },
                               media: (@MainActor (MockBackend) -> Void)? = nil,
                               deviations: [FigmaDeviation] = []) -> GalleryEntry {
        return GalleryEntry(id: id, title: title, size: size, figmaNode: node, screens: screens,
                            colorScheme: light ? .light : .dark,
                            notes: notes ?? "Shipping composition (D030): product defaults, PiP action and native traffic lights as in the real window. Differences from Figma here are real product differences.",
                            renderEngine: .shippingWindow, backdropMode: .liveMaterial, figmaDeviations: deviations) {
            let mock = MockBackend(scenario: scenario)
            if autoHide { mock.settings.setValue(.string("always"), for: "macosx-redesign-autohide", apply: .nextMedia) }
            media?(mock)
            let app = mock.makeAppModel()
            configure(app)
            return host(app) {
                MXRAppView(videoView: scenario == .music || scenario == .idle ? AnyView(Color.clear) : PlayerGallery.catVideo(windowSize: size),
                           onPictureInPicture: {}, engineVersion: nil)
            }
        }
    }

    /// D022 (D055 bullet "S01.Window/shipping top bar"): the Mac top bar against Figma's Windows one.
    /// The left group is compared where the product draws it, after the traffic lights (it moves by
    /// the lights' reserve, as `MXRTopBar` lays it out); minimise and maximise are not on a Mac; the
    /// fullscreen button takes the place of Windows' close at the right end and is compared there.
    @MainActor
    static func macTopBar(leftGroup: String, minimize: String, maximize: String, fullscreen: String) -> [FigmaDeviation] {
        let bar = Theme.Metric.Window.self
        let shift = max(0, ShippingWindowControls.measured.reserve - bar.topBar.padding.leading) + bar.topBarLeftGroup.gap
        return [
            .moved(node: leftGroup, by: CGSize(width: shift, height: 0), decision: "D022",
                   "the native traffic lights lead the top bar and the left group follows them"),
            .differs(node: minimize, decision: "D022", "Windows minimise: the Mac window has its traffic lights instead"),
            .differs(node: maximize, decision: "D022", "Windows maximise: the Mac window has its traffic lights instead"),
            .moved(node: fullscreen, by: CGSize(width: bar.windowControlCell.width, height: 0), decision: "D022",
                   "with no Windows close, the fullscreen button ends the bar"),
        ]
    }

    /// Sets up a whole-window scene the way the real window does, for whatever canvas renders it:
    /// the scheme and accent of the render (the entry's own, or `--scheme`/`--accent`) go into the
    /// AppModel, because MXRAppView themes itself from ``AppearanceModel``. In the shipping window
    /// (an S*.Window entry, or an App entry rendered with `--engine shipping-window`) the top bar also
    /// keeps the measured traffic-light reserve and the buttons follow the bars, as
    /// `MXRAppController` does; without them the cone sat under the traffic lights.
    @MainActor
    static func host<Content: View>(_ app: AppModel, @ViewBuilder content: @escaping () -> Content) -> AnyView {
        if let environment = GalleryRenderContext.current?.environment {
            app.appearance.setTheme(environment.colorScheme == .light ? .light : .dark)
            if let accent = environment.accent.flatMap(AccentChoice.init(rawValue:)) { app.appearance.setAccent(accent) }
        }
        guard GalleryRenderContext.current?.engine == .shippingWindow else { return AnyView(content().appModel(app)) }
        app.interface.windowControlsReserve = app.player.isFullscreen ? 0 : ShippingWindowControls.measured.reserve
        return AnyView(ShippingWindowFrame(content: content).appModel(app))
    }
}

extension ShippingGallery {
    /// The media Player - Light (2425:13624) shows: The Wand S01E04 paused at 00:02:10 of 00:25:40,
    /// alone in the queue (Previous and Next disabled), volume 80 % (53 pt fill). Media data only (D030).
    @MainActor
    static func figmaPlayerLight(_ mock: MockBackend) {
        guard var episode = mock.player.currentMedia else { return }
        episode.duration = .hms(0, 25, 40)
        mock.queue.setItems([episode], current: 0)
        mock.player.load(episode, at: .hms(0, 2, 10), state: .paused)
        mock.player.setVolume(0.8)
    }

    /// The media Player - customize-7 (2160:8301) shows: The Wand S01E11 paused at 00:02:10 of 00:25:40,
    /// mid-queue (Previous and Next enabled, 2160:8306), volume 50 % (33 pt fill). Media data only (D030).
    @MainActor
    static func figmaCustomize7(_ mock: MockBackend) {
        guard var episode = mock.player.currentMedia else { return }
        episode.duration = .hms(0, 25, 40)
        let previous = mock.queue.items.isEmpty ? [] : [mock.library.mediaItem(id: "ml:wand-s01e10")].compactMap { $0 }
        let following = mock.queue.items.dropFirst().map(\.media)
        mock.queue.setItems(previous + [episode] + following, current: previous.count)
        mock.player.load(episode, at: .hms(0, 2, 10), state: .paused)
        mock.player.setVolume(0.5)
    }

    /// The media Player-6 (247:445) shows (A-05). Only media data, so product defaults stay (D030):
    /// an untagged local file outside the library ("VLC Media Player" title, "Videos" chip, A-01/A-04),
    /// paused at 00:02:10 of 00:25:40, mid-queue (Previous and Next enabled), volume 50 % (33 pt fill).
    @MainActor
    static func figmaPlayer6(_ mock: MockBackend) {
        func clip(_ name: String) -> MediaItem {
            MediaItem(id: "figma-player-6-\(name)", mrl: URL(fileURLWithPath: "/Users/Shared/Movies/\(name).mp4").absoluteString,
                      title: "\(name).mp4", fileName: "\(name).mp4", kind: .video, duration: .hms(0, 25, 40),
                      videoSize: CGSize(width: 1920, height: 1080))
        }
        let items = [clip("Intro"), clip("VLC Media Player"), clip("Outro")]
        mock.queue.setItems(items, current: 1)
        mock.player.load(items[1], at: .hms(0, 2, 10), state: .paused)
        mock.player.setVolume(0.5)
    }
}

/// The traffic lights as AppKit lays them out in the real window (``MXRWindowControls/configure(_:)``),
/// measured once from an off-screen window of the shipping style.
@MainActor
enum ShippingWindowControls {
    struct Measurement {
        var reserve: Double
    }

    static let measured: Measurement = {
        let size = Theme.Metric.Window.player.size
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        MXRWindowControls.configure(window)
        window.contentView?.layoutSubtreeIfNeeded()
        window.layoutIfNeeded()
        let reserve = Double(MXRWindowControls.leadingReserve(in: window))
        window.close()
        return Measurement(reserve: reserve)
    }()
}

/// Shares the native window's button visibility with the shipping interface state.
/// Buttons remain in the titlebar; component canvases intentionally do not imitate them.
private struct ShippingWindowFrame<Content: View>: View {
    @Environment(AppModel.self) private var app
    @ViewBuilder let content: () -> Content

    var body: some View {
        // MXRAppController: the lights follow the top bar and Hide UI; in fullscreen macOS shows them
        // only in its own titlebar with the menu bar, and the cone moves to the edge (reserve 0).
        content()
            .background(ShippingWindowButtonVisibility(
                hidden: !app.interface.isTopBarVisible || app.interface.isUIHidden || app.player.isFullscreen))
    }
}

private struct ShippingWindowButtonVisibility: NSViewRepresentable {
    var hidden: Bool
    func makeNSView(context: Context) -> ButtonVisibilityView { ButtonVisibilityView(hidden: hidden) }
    func updateNSView(_ view: ButtonVisibilityView, context: Context) { view.buttonsHidden = hidden; view.updateButtons() }

    final class ButtonVisibilityView: NSView {
        var buttonsHidden: Bool
        init(hidden: Bool) { buttonsHidden = hidden; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateButtons() }
        func updateButtons() {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window?.standardWindowButton(type)?.isHidden = buttonsHidden
            }
        }
    }
}
