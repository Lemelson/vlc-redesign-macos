import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

/// Real SwiftUI player states. Artwork is a licensed media fixture, never a rendered UI screenshot.
final class PlayerGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let control = Theme.Metric.ControlBar.self
        var entries: [GalleryEntry] = [
            GalleryEntry(id: "C.PlayButton/play", title: "Play", size: control.playButton.size,
                         figmaNode: control.playButton.node, screens: ["S01"]) {
                MXRPlayPauseButton().appModel(videoApp())
            },
            GalleryEntry(id: "C.PlayButton/pause", title: "Pause", size: control.pauseButton.size,
                         figmaNode: control.pauseButton.node, screens: ["S01"]) {
                MXRPlayPauseButton().appModel(videoApp(playing: true))
            },
            GalleryEntry(id: "C.CurrentTime/default", title: "Editable elapsed time", size: control.timeLabel.size,
                         figmaNode: "1904:7237", screens: ["S02"]) {
                MXRTimeLabel().appModel(videoApp())
            },
            GalleryEntry(id: "C.Duration/default", title: "Duration", size: control.timeLabel.size,
                         figmaNode: "1905:7313", screens: ["S02"]) {
                MXRTimeLabel(.duration).appModel(videoApp())
            },
            GalleryEntry(id: "C.Duration/remaining", title: "Remaining time", size: control.timeLabel.size,
                         figmaNode: "1905:7317", screens: ["S02"]) {
                let app = videoApp(); app.interface.timeDisplay = .remaining
                return MXRTimeLabel(.duration).appModel(app)
            },
            GalleryEntry(id: "C.SeekBar/default", title: "Seek bar", size: control.seekTrack.size,
                         figmaNode: control.seekTrack.node, screens: ["S03"],
                         notes: "Bar only, so the fixture is the time Figma 1908:7387 draws (head x 92 = 113 s of 1540); its labels' 02:10 sits 13.5 pt further right (D048).",
                         renderEngine: .hostingView) {
                let app = videoApp(at: .hms(0, 1, 53))
                return MXRSeekBar().appModel(app)
            },
            GalleryEntry(id: "C.SeekPreview/default", title: "Thumbnail preview", size: control.seekThumbnail.size,
                         figmaNode: control.seekThumbnail.node, screens: ["S03"], renderEngine: .hostingView) {
                let app = videoApp(); app.seekPreview.debounce = .zero; app.seekPreview.hover(at: 130)
                return MXRSeekPreview().appModel(app)
            },
            GalleryEntry(id: "C.VolumeTooltip/default", title: "Volume tooltip", size: control.volumeTooltip.size,
                         figmaNode: control.volumeTooltip.node, screens: ["S04"]) {
                let app = videoApp(); app.player.setVolume(1)
                return MXRVolumeTooltip().appModel(app)
            },
            GalleryEntry(id: "S01.ControlBar/default", title: "Video control bar", size: control.bar.size,
                         figmaNode: control.bar.node, screens: ["S01", "S02", "S03", "S04"],
                         notes: "Figma labels 130/1540 seconds while its head is ~0.073 along the track; this view keeps the real clock ratio ~0.0844.", renderEngine: .hostingView,
                         figmaDeviations: [
                            .differs(node: "1908:7389", outset: 14, decision: "D048", "head at the labelled 00:02:10; Figma draws it at 00:01:53"),
                            .differs(CGRect(x: 0, y: 0, width: control.bar.width, height: Theme.Stroke.hairline), decision: "D048",
                                     "no top stroke in dark, as in Player-6"),
                         ]) {
                let app = videoApp()
                return MXRControlBar().appModel(app)
            },
            GalleryEntry(id: "S01.ControlBar/compact", title: "Compact playback controls",
                         size: CGSize(width: Theme.Metric.Window.player.width / 4, height: control.bar.height),
                         screens: ["S01"], notes: "480 pt window minimum: configured primary controls remain visible, with other actions in overflow.",
                         renderEngine: .hostingView) {
                let app = videoApp()
                return MXRControlBar().appModel(app)
            },
            // Screens use the shipping composition (D030): MXRAppView with product defaults. Only the
            // media fixture (title, folder, position) is chosen to match the Figma frame.
            GalleryEntry(id: "S01.Player/default", title: "Default player", size: Theme.Metric.Window.player.size,
                         screens: ["S01"],
                         notes: "Shipping composition without the native titlebar; see S01.Window/shipping for the Figma check. Figma labels 130/1540 seconds but head fraction is ~0.079; playback uses the real clock ratio.",
                         renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(figmaMedia: true)
                return screen(app)
            },
            GalleryEntry(id: "S01.Player/compact", title: "Minimum native player window",
                         size: CGSize(width: Theme.Metric.Window.player.width / 4, height: Theme.Metric.Window.player.height / 4),
                         screens: ["S01"], renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(figmaMedia: true)
                return screen(app, size: CGSize(width: Theme.Metric.Window.player.width / 4, height: Theme.Metric.Window.player.height / 4))
            },
            GalleryEntry(id: "S05.Player/fullscreen", title: "Fullscreen, bars revealed", size: Theme.Metric.Window.player.size,
                         screens: ["S05"], renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(playing: true); app.player.setFullscreen(true)
                return screen(app)
            },
            GalleryEntry(id: "S05.Player/fullscreen-top", title: "Fullscreen, pointer near the top", size: Theme.Metric.Window.player.size,
                         screens: ["S05"], notes: "D023: the top bar reveals on its own (video 03m51.0).",
                         renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(playing: true); app.player.setFullscreen(true)
                app.interface.isTopBarVisible = true; app.interface.isControlBarVisible = false
                return screen(app)
            },
            GalleryEntry(id: "S05.Player/fullscreen-bottom", title: "Fullscreen, pointer near the bottom", size: Theme.Metric.Window.player.size,
                         screens: ["S05"], notes: "D023: the control bar reveals on its own (video 03m53.0).",
                         renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(playing: true); app.player.setFullscreen(true)
                app.interface.isTopBarVisible = false; app.interface.isControlBarVisible = true
                return screen(app)
            },
            GalleryEntry(id: "S05.Player/fullscreen-hidden", title: "Fullscreen, bars hidden", size: Theme.Metric.Window.player.size,
                         screens: ["S05"], notes: "§03: no frame in fullscreen.", renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(playing: true); app.player.setFullscreen(true)
                app.interface.areBarsVisible = false
                return screen(app)
            },
            GalleryEntry(id: "S06.Player/hidden-ui", title: "Hidden UI", size: Theme.Metric.Window.player.size,
                         figmaNode: "3328:11554", screens: ["S06"],
                         notes: "Cat media retains window coordinates; missing outer 20 pt edges are inferred from adjacent media pixels.", renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(); app.interface.isUIHidden = true
                return screen(app)
            },
            GalleryEntry(id: "S07.AppMenu/default", title: "VLC menu", size: Theme.Metric.Menus.appMenu.size,
                         figmaNode: Theme.Metric.Menus.appMenu.node, screens: ["S07", "S08", "S11"], renderEngine: .hostingView) {
                MXRAppMenuView().appModel(videoApp())
            },
            GalleryEntry(id: "S09.ContextMenu/default", title: "Video context menu", size: Theme.Metric.Menus.rightClickMenu.size,
                         figmaNode: Theme.Metric.Menus.rightClickMenu.node, screens: ["S09", "S10"], renderEngine: .hostingView) {
                MXRVideoContextMenuView().appModel(videoApp())
            },
            GalleryEntry(id: "S12.ContinueWatching/default", title: "Continue watching", size: Theme.Metric.Dialogs.resumeToast.size,
                         screens: ["S12"],
                         notes: "1919:9580 is hidden in Figma; geometry follows the layer, without a pixel reference.") {
                MXRContinueWatchingToast().appModel(AppModel.mock(.continueWatching))
            },
            GalleryEntry(id: "S12.Player/continue-watching", title: "Player with restore prompt", size: Theme.Metric.Window.player.size,
                         screens: ["S12"], renderEngine: .hostingView, backdropMode: .liveMaterial) {
                screen(AppModel.mock(.continueWatching))
            },
            GalleryEntry(id: "S13.Player/osd", title: "OSD with pressed key", size: Theme.Metric.Window.player.size,
                         screens: ["S13"], renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let app = videoApp(); app.osd.show("Crop: 2.35:1", pressedKey: "C")
                return screen(app)
            },
            GalleryEntry(id: "S34.Player/music", title: "Music now playing", size: Theme.Metric.Window.player.size,
                         figmaNode: "4767:23726", screens: ["S34"],
                         notes: "Product defaults: the solid seek bar, because \"Show Waveform on Seekbar\" is off until the user turns it on (D028; video 09m17.5 shows it OFF, 12m: \"the waveform seekbar if you want\"). S34.Player/music-waveform draws the opt-in. Native controls replace Windows cells (D007).", renderEngine: .hostingView, backdropMode: .liveMaterial,
                         figmaDeviations: [
                            .differs(node: "I4767:23748;4778:26191", outset: 4, decision: "D028",
                                     "solid seek bar by default; Figma draws the opt-in waveform"),
                         ]) {
                let app = musicApp()
                return ShippingGallery.host(app) { MXRAppView() }
            },
            GalleryEntry(id: "S34.Player/music-waveform", title: "Music now playing, waveform on", size: Theme.Metric.Window.player.size,
                         figmaNode: "4767:23726", screens: ["S34"],
                         notes: "The user turned \"Show Waveform on Seekbar\" on (Playback tab, D028), as in video 12m56.6. Figma labels 10/100 seconds while its head sits at ~0.0797 of the track; the head stays at the labelled 0.1 (D048).", renderEngine: .hostingView, backdropMode: .liveMaterial,
                         figmaDeviations: [
                            // From Figma's head (x 426, I4767:23748;4778:26192) to the labelled 00:00:10 (x 458).
                            .differs(CGRect(x: 420, y: 1039, width: 44, height: 28), decision: "D048",
                                     "head at the labelled 00:00:10; Figma draws it at 0.0797 of the track"),
                         ]) {
                let app = musicApp()
                app.interface.showWaveform = true
                return ShippingGallery.host(app) { MXRAppView() }
            },
            GalleryEntry(id: "S34.ControlBar/music", title: "Music control bar", size: control.bar.size,
                         figmaNode: "4778:26181", screens: ["S34"],
                         notes: "The standalone component has 130/1540 seconds and audio/settings/queue cells. Its illustrative head is ~0.079; playback uses ~0.0844. Figma clips its 244 waveform bars beyond the 1204 pt track; native fits peaks from the entire signal at fixed spacing so late audio remains represented.", renderEngine: .hostingView,
                         figmaDeviations: [
                            .differs(node: "4778:26192", outset: 8, decision: "D048", "head at the labelled 00:02:10, one waveform step right of Figma's"),
                            .differs(CGRect(x: 0, y: 0, width: control.bar.width, height: Theme.Stroke.hairline), decision: "D048",
                                     "no top stroke in dark, as in Player-6"),
                         ]) {
                let app = musicApp(componentReference: true)
                return MXRControlBar().appModel(app)
            },
            GalleryEntry(id: "S01.Player/live-stream", title: "Live stream without seeking", size: Theme.Metric.Window.player.size,
                         screens: ["S01", "S02", "S03"], renderEngine: .hostingView, backdropMode: .liveMaterial) {
                ShippingGallery.host(AppModel.mock(.stream)) { MXRAppView() }
            },
        ]
        let volumes: [(Int, String)] = [(0, "244:185"), (10, "244:190"), (20, "244:195"), (30, "244:200"),
                                       (40, "244:205"), (50, "244:210"), (60, "244:215"), (70, "244:220"),
                                       (80, "244:225"), (90, "244:230"), (100, "244:235"), (150, "244:240"), (200, "244:183")]
        for (percent, node) in volumes {
            entries.append(GalleryEntry(id: "C.VolumeCone/\(percent)", title: "Volume \(percent)%", size: Theme.Metric.Volume.cone.size,
                                        figmaNode: node, screens: ["S04"]) {
                let app = videoApp(); app.player.setVolume(Double(percent) / 100)
                return MXRVolumeCone().appModel(app)
            })
        }
        return entries
    }

    @MainActor private static func videoApp(playing: Bool = false, figmaMedia: Bool = false,
                                            at time: MediaTime = .hms(0, 2, 10)) -> AppModel {
        let mock = MockBackend(scenario: .playingEpisode)
        if var media = mock.player.currentMedia {
            mock.queue.setItems([media, media, media], current: 1)
            media.duration = .hms(0, 25, 40)
            if figmaMedia { media.episode = nil; media.title = "VLC Media Player"; media.folder = FolderReference(id: "videos", name: "Videos") }
            mock.player.load(media, at: time, state: playing ? .playing : .paused)
        }
        mock.player.setVolume(0.5)
        return mock.makeAppModel()
    }

    /// The shipping window content for `app` with the cat media fixture as the video.
    @MainActor private static func screen(_ app: AppModel, size: CGSize = Theme.Metric.Window.player.size) -> some View {
        ShippingGallery.host(app) { MXRAppView(videoView: catVideo(windowSize: size)) }
    }

    @MainActor static func catVideo(windowSize: CGSize = Theme.Metric.Window.player.size) -> AnyView {
        if let image = MockArtwork.image(named: "player-cat-canonical", maxPixelSize: CGSize(width: 3840, height: 2160)) {
            return AnyView(PlayerGalleryVideoCanvas(image: image, windowSize: windowSize))
        }
        return AnyView(Rectangle().fill(Theme.Color.thumbPlaceholder))
    }

    @MainActor private static func musicApp(componentReference: Bool = false) -> AppModel {
        let mock = MockBackend(scenario: .music)
        if componentReference, var media = mock.player.currentMedia {
            media.duration = .hms(0, 25, 40)
            mock.player.load(media, at: .hms(0, 2, 10), state: .paused)
        }
        mock.queue.setItems([MockMediaID.moonlight, MockMediaID.untangle, MockMediaID.blackBird]
            .compactMap { mock.library.mediaItem(id: $0) }, current: 1)
        mock.settings.setValue(.bool(false), for: "macosx-redesign-title-filename", apply: .nextMedia)
        let app = mock.makeAppModel()
        if componentReference {
            app.interface.showWaveform = true // the Figma component draws the opt-in waveform (D028); screens keep the default
            app.layouts.beginEditing(profileID: app.profiles.currentID, kind: .music)
            app.layouts.updateDraft { layout in
                layout.bottom[0].insert(LayoutItem(.playbackSettings, id: "figma-music-settings"),
                                        at: layout.bottom[0].count - 1)
            }
        }
        app.player.pause(); app.player.setVolume(0.5)
        return app
    }
}

/// The source is the whole 1920×1080 window paint. The canvas shows the part under its own frame,
/// read in the window's coordinate space, so the media keeps its Figma position in every layout.
/// The inferred outer 20 pt edges contain media only.
public struct PlayerGalleryVideoCanvas: View {
    private let image: CGImage
    private let windowSize: CGSize

    public init(image: CGImage, windowSize: CGSize = Theme.Metric.Window.player.size) {
        self.image = image; self.windowSize = windowSize
    }

    public var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named(MXRAppView.coordinateSpace))
            Image(decorative: image, scale: 2).resizable()
                .frame(width: windowSize.width, height: windowSize.height)
                .offset(x: -frame.minX, y: -frame.minY)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
