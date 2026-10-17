import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

final class PanelsGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let tracks = Theme.Metric.SidePanels.tracksPopup.size
        let sidebar = Theme.Metric.SidePanels.settingsSidebar.size
        let queue = Theme.Metric.SidePanels.queuePanel.size
        return [
            GalleryEntry(id: "S14.Tracks/subtitles", title: "Subtitle tracks", size: tracks, figmaNode: "491:2243", screens: ["S14"],
                         notes: "Keeps the Embedded/External divider of video 06m21.7 and the Audio tab (496:2652) in the Audio tab's geometry; the External header sits 0.5 pt below 491:2243's (D054).",
                         renderEngine: .hostingView) {
                MXRTrackPopoverView(tab: .subtitles).appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S15.Tracks/audio", title: "Audio tracks and output device", size: tracks, figmaNode: "496:2523", screens: ["S15"], renderEngine: .hostingView) {
                MXRTrackPopoverView(tab: .audio).appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S16.Tracks/video", title: "Video tracks", size: tracks, figmaNode: "498:2702", screens: ["S16"], renderEngine: .hostingView) {
                MXRTrackPopoverView(tab: .video).appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S17.Sidebar/playback", title: "Playback sidebar", size: sidebar, figmaNode: "5187:24308", screens: ["S17"],
                         notes: "Rows follow the complete list at 09m17.5 (Show Waveform and Show Metadata replace the Figma crop's Show Statistics). Reverse is shown unavailable with an ⓘ (D014: Core plays forward only).", renderEngine: .hostingView) {
                let app = sidebarApp()
                // 5187:24308 shows the timeline toggle usable: play the episode's external .srt
                // subtitle, whose cue times the timeline can read (CMP-17), rather than an embedded one.
                if let external = app.tracks.externalTracks(of: .subtitle).first { app.tracks.select(external) }
                return MXRSettingsSidebarView(tab: .playback).appModel(app)
            },
            GalleryEntry(id: "S17.Metadata/overlay", title: "Show Metadata overlay", size: CGSize(width: tracks.width, height: metadataHeight), screens: ["S17"],
                         notes: "Playback tab \"Show Metadata\" ON. Figma has no frame (§07 OPEN); built from the side-panel surface and caption type.", renderEngine: .hostingView) {
                let app = AppModel.mock(.playingEpisode)
                app.interface.showMetadata = true
                return MXRMetadataOverlayView().appModel(app).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            },
            GalleryEntry(id: "S20.Presets/open", title: "Preset list", size: CGSize(width: presetListWidth, height: presetListHeight), figmaNode: "2372:8838", screens: ["S20"],
                         notes: "Figma's presets: New first, saved presets with ⋯, the current Default Preset last and checked.", renderEngine: .hostingView) {
                MXRSidebarPresetList().appModel(presetApp()).frame(maxHeight: .infinity, alignment: .bottom)
            },
            GalleryEntry(id: "S18.Sidebar/video", title: "Video sidebar", size: sidebar, figmaNode: "498:2965", screens: ["S18"], renderEngine: .hostingView) {
                MXRSettingsSidebarView(tab: .video).appModel(sidebarApp())
            },
            GalleryEntry(id: "S19.Sidebar/audio", title: "Audio sidebar", size: sidebar, figmaNode: "536:1087", screens: ["S19"], renderEngine: .hostingView) {
                MXRSettingsSidebarView(tab: .audio).appModel(sidebarApp())
            },
            GalleryEntry(id: "S20.Sidebar/subtitles", title: "Subtitles sidebar", size: sidebar, figmaNode: "763:1986", screens: ["S20"], renderEngine: .hostingView) {
                let app = sidebarApp()
                app.tracks.setSubtitleDelay(-4)
                app.tracks.setSubtitleFPS(1)
                app.tracks.updateSubtitleStyle { $0.fontFamily = "Inter"; $0.textColor = MXRCore.RGBColor(vlcValue: 0xB8B8B8); $0.outlineColor = MXRCore.RGBColor(vlcValue: 0x0C0C0C); $0.useEmbeddedStyles = false }
                return MXRSettingsSidebarView(tab: .subtitles).appModel(app)
            },
            GalleryEntry(id: "S20.Sidebar/subtitles-appearance", title: "Subtitles sidebar · Appearance (Relative)", size: CGSize(width: sidebar.width, height: appearanceHeight),
                         screens: ["S20"],
                         // No figmaNode: frame 800:1126 is clipped by its scroll view in renders/Controls.png, so
                         // the word-slider rows are absent from the render and a pixel compare can only fail on size.
                         notes: "The Appearance section scrolled into view (frame 800:1126, clipped in renders/Controls.png; compare row geometry with figma_file.json). Relative mode: Font Size, Outline Thickness and Background Opacity are text values over ticked sliders (804:1341, 804:1342, 848:1686): 86 pt rows on a 91 pt pitch, 6/4/11 stops.",
                         renderEngine: .hostingView) {
                MXRSidebarContentPreview(tab: .subtitles).appModel(appearanceApp(.relative))
            },
            GalleryEntry(id: "S20.Sidebar/subtitles-appearance-pixels", title: "Subtitles sidebar · Appearance (Pixels)", size: CGSize(width: sidebar.width, height: appearanceHeight),
                         screens: ["S20"],
                         notes: "Pixels mode as at 07m52.9: Font Size 18px, Outline Thickness 2px and Background Opacity 0% are plain fields (no Figma frame).",
                         renderEngine: .hostingView) {
                MXRSidebarContentPreview(tab: .subtitles).appModel(appearanceApp(.pixels))
            },
            GalleryEntry(id: "S21.Timeline/default", title: "Subtitle timeline", size: Theme.Metric.ControlBar.seekGroup.size, figmaNode: "3744:12369", screens: ["S21"],
                         notes: "Canonical 01:50–02:40 cue fixture from 3744:12371. Figma's elapsed fill ends 17 pt before its playhead; runtime keeps them aligned.", renderEngine: .hostingView,
                         figmaDeviations: [.differs(node: "3744:12373", outset: 18, decision: "D048",
                                                    "the played fill reaches the head (video 07m04.2); Figma leaves a 17 pt gap")]) {
                let mock = MockBackend(scenario: .playingEpisode)
                mock.player.setSubtitleCues(timelineCues())
                let app = mock.makeAppModel(clockTicks: false)
                app.tracks.setSubtitleDelay(.zero)
                app.player.seek(to: 135)
                app.tracks.loadSubtitleCues()
                return MXRSubtitleTimelineView().appModel(app).background(Theme.Color.bgA3Transparent)
            },
            GalleryEntry(id: "S22.Queue/default", title: "Play queue", size: queue, figmaNode: "463:831", screens: ["S22"],
                         notes: "Exact Figma row filenames and durations. Their sum is 1h35m59s; the reference's 2h3m header is inconsistent, so the model calculates the total.", renderEngine: .hostingView) {
                MXRQueuePanelView().appModel(queueApp())
            },
            GalleryEntry(id: "S23.Queue/bookmarks", title: "Bookmarks", size: queue, figmaNode: "6320:13784", screens: ["S23"], renderEngine: .hostingView) {
                MXRQueuePanelView(tab: .bookmarks).appModel(AppModel.mock(.playingMovie))
            },
            GalleryEntry(id: "S24.Queue/chapters", title: "Chapters", size: queue, figmaNode: "6321:14045", screens: ["S24"], renderEngine: .hostingView) {
                MXRQueuePanelView(tab: .chapters).appModel(AppModel.mock(.playingMovie))
            },
            GalleryEntry(id: "S21.App/subtitle-timeline", title: "Player · subtitle timeline, metadata and Playback tab", size: Theme.Metric.Window.player.size,
                         screens: ["S17", "S21"],
                         notes: "Shipping composition (D030) with the three Playback toggles a viewer turns on: the bar's time slots show the window bounds with \"*\", the metadata card sits bottom-left.",
                         renderEngine: .hostingView, backdropMode: .liveMaterial) {
                let mock = MockBackend(scenario: .playingEpisode)
                mock.player.setSubtitleCues(timelineCues())
                let app = mock.makeAppModel()
                app.player.pause()
                app.player.seek(to: 135)
                app.tracks.setSubtitleDelay(.zero)
                app.tracks.loadSubtitleCues()
                app.interface.showSubtitleTimeline = true
                app.interface.showMetadata = true
                app.interface.rightPanel = .sidebar(.playback)
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo()) }
            },
        ] + filterCardEntries() + responsiveEntries() + [
            GalleryEntry(id: "S18.Filters/engineOptions", title: "Video filter option inspector", size: sidebar, screens: ["S18"],
                         notes: "Expanded inspector using real VLC option names, types, ranges and choices; detailed Geometry/Overlay/Advanced layouts are unspecified in Figma.", renderEngine: .hostingView) {
                ScrollView { MXRVideoFilterOptionsView(expanded: true) }
                    .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2).background(Theme.Color.bgB1Transparent)
                    .appModel(filterOptionsApp())
            },
        ]
    }
    /// Cue rectangles in 3749:12473–12484, converted from the 1234 pt inner track to media time.
    private static func timelineCues() -> [SubtitleCue] {
        let rectangles: [(Double, Double)] = [(5.5, 20), (45.5, 12), (71.5, 31), (123.5, 82), (241.5, 83), (359.5, 35),
                                                  (510.5, 21), (633.5, 113), (767.5, 73), (901.5, 66), (995.5, 49), (1106.5, 49)]
        return rectangles.enumerated().map { index, rectangle in
            let start = 110 + (rectangle.0 - 2) / 1234 * 50
            return SubtitleCue(start: .seconds(start), end: .seconds(start + rectangle.1 / 1234 * 50), text: "Cue \(index + 1)")
        }
    }
    @MainActor private static func queueApp() -> AppModel {
        let mock = MockBackend(scenario: .pausedEpisode)
        let media = mock.queue.items.map { item in
            var media = item.media
            media.fileName = media.fileName?.replacingOccurrences(of: "The_Wand", with: "The Wand")
            return media
        }
        // 463:850/491:2378: this isolated Figma queue has no current row, even though the player has media.
        mock.queue.setItems(media, current: nil)
        return mock.makeAppModel(clockTicks: false)
    }
    @MainActor private static func filterOptionsApp() -> AppModel {
        var catalog = SettingsCatalog.bundled
        // Source metadata: modules/video_filter/puzzle/puzzle.c and rotate.c, modules/spu/marq.c.
        let rows: [SettingsRow] = [
            .init(option: "puzzle-rows", control: .number, label: "Number of rows", min: 2, max: 42, mock: .integer(4)),
            .init(option: "puzzle-cols", control: .number, label: "Number of columns", min: 2, max: 42, mock: .integer(4)),
            .init(option: "rotate-angle", control: .number, label: "Angle in degrees", mock: .float(30)),
            .init(option: "marq-marquee", control: .text, label: "Text", mock: .string("VLC")),
            .init(option: "marq-opacity", control: .number, label: "Opacity", min: 0, max: 255, mock: .integer(255)),
            .init(option: "video-filter", control: .text, label: "Video filter chain", mock: .string("")),
        ]
        catalog.categories.append(.init(id: "panel-filter-fixture", group: .media, sidebar: "Video filters", title: "Video filters", icon: "video", sections: [.init(title: "Options", rows: rows)]))
        return MockBackend(scenario: .playingEpisode, settingsCatalog: catalog).makeAppModel(clockTicks: false)
    }
    /// The filter cards' component sets, each open variant on its own (360 pt wide, Figma height),
    /// plus the closed bar they share.
    @MainActor private static func filterCardEntries() -> [Any] {
        let width = Theme.Metric.SidePanels.settingsSidebar.size.width - 2 * Theme.Spacing.gap20
        let cards: [(MXRFilterCard, String, String, CGFloat)] = [
            (.essential, "S18", "536:1860", 666), (.crop, "S18", "543:995", 152), (.colors, "S18", "614:1435", 755),
            (.equalizer, "S19", "6114:13615", 1048), (.compressor, "S19", "536:1514", 590),
            (.spatializer, "S19", "536:1708", 438), (.stereoWidener, "S19", "612:1228", 362),
        ]
        let open: [Any] = cards.map { card, screen, node, height in
            GalleryEntry(id: "\(screen).Filters/\(card.rawValue)-open", title: "Filter card · \(card.rawValue), open",
                         size: CGSize(width: width, height: height), figmaNode: node, screens: [screen],
                         notes: "The open card: one BG/A3 container with the Collapse Settings header and the rows (08m49.0). Thumbs sit at their values in VLC's ranges and Stereo Widener factors have no \"%\" (D054).",
                         renderEngine: .hostingView, figmaDeviations: filterCardDeviations[card] ?? []) {
                MXRFilterCardPreview(card).appModel(filterCardApp())
            }
        }
        return open + [
            GalleryEntry(id: "S18.Filters/card-closed", title: "Filter card · closed", size: CGSize(width: width, height: closedCardHeight),
                         figmaNode: "536:1856", screens: ["S18", "S19"], renderEngine: .hostingView) {
                MXRFilterCardPreview(.essential, expanded: false).appModel(filterCardApp())
            },
        ]
    }
    /// D054: where an open card's Figma thumb disagrees with its own label, the product puts the
    /// thumb at the label's value in the VLC module's range; Compressor's "FM5" is a typo of RMS and
    /// Stereo Widener's 0–1 factors carry no "%". Only those sliders and labels are left out.
    private static let filterCardDeviations: [MXRFilterCard: [FigmaDeviation]] = [
        .compressor: [
            .differs(node: "536:1543", outset: 2, decision: "D054", "\"RMS / Peak\", Figma's \"FM5\" is a typo of VLC's option"),
        ] + [("536:1545", "RMS / Peak 0.2 of 0–1"), ("536:1604", "Attack 25 ms of 1.5–400 ms"), ("536:1622", "Release 100 ms of 2–800 ms"),
             ("536:1654", "Ratio 4 : 1 of 1–20"), ("536:1670", "Knee 5 dB of 1–10 dB"), ("536:1686", "Makeup 7 dB of 0–24 dB")].map {
            FigmaDeviation.differs(node: $0.0, outset: 1, decision: "D054", "thumb at \($0.1) (compressor.c); Figma's is illustrative")
        },
        .stereoWidener: [
            .differs(node: "612:1236", outset: 1, decision: "D054", "Delay thumb at 20 ms of 1–100 ms (stereo_widen.c); Figma's 26 % is illustrative"),
        ] + ["612:1256", "612:1276", "612:1296"].map {
            FigmaDeviation.differs(node: $0, outset: 2, decision: "D054", "a 0–1 factor (stereo_widen.c), no \"%\"")
        },
    ]
    /// Figma's illustrative values where they differ from VLC's defaults: Banding Removal Radius 14
    /// and Film Grain Variance 2 (539:885, 536:1919), threshold sliders at 50 of 0–255 (614:1483's thumb
    /// at 64 pt: 2 + 50/255 of the 316 pt travel; Figma shows no number), Cartoon
    /// off (673:1686), Sepia Intensity at a third (673:1702), Spatializer Size 8.0 (536:1715) and
    /// Feedback Gain 0.2 (612:1255).
    @MainActor private static func filterCardApp() -> AppModel {
        let app = AppModel.mock(.playingEpisode)
        app.videoEffects.updateEssential { $0.bandingRemovalRadius = 14; $0.filmGrainVariance = 2 }
        app.videoEffects.update { $0.colors.thresholdSaturation = 50; $0.colors.thresholdSimilarity = 50; $0.colors.cartoon = false }
        app.videoEffects.setSepiaIntensity(85)
        app.audioEffects.update { $0.spatializer.roomSize = 0.8; $0.stereoWidener.feedback = 0.2 }
        return app
    }
    @MainActor private static func responsiveEntries() -> [Any] {
        let sizes = [("compact", CGSize(width: 307, height: 450)), ("minimum", CGSize(width: 307, height: 180))]
        return sizes.flatMap { variant, size in
            [
                GalleryEntry(id: "S18.Sidebar/\(variant)", title: "Video sidebar · \(variant)", size: size, screens: ["S18"], renderEngine: .hostingView) {
                    MXRSettingsSidebarView(tab: .video).appModel(sidebarApp())
                },
                GalleryEntry(id: "S22.Queue/\(variant)", title: "Queue · \(variant)", size: size, screens: ["S22"], renderEngine: .hostingView) {
                    MXRQueuePanelView().appModel(AppModel.mock(.pausedEpisode))
                },
                GalleryEntry(id: "S14.Tracks/\(variant)", title: "Subtitle tracks · \(variant)", size: size, screens: ["S14"], renderEngine: .hostingView) {
                    MXRTrackPopoverView().appModel(AppModel.mock(.playingEpisode))
                },
            ]
        }
    }
    /// 2372:8838: 364 pt wide card, 2 pt padding and gaps around six 38 pt rows.
    private static let presetListWidth: CGFloat = 364
    private static let presetListHeight: CGFloat = 242
    private static let metadataHeight: CGFloat = 200
    /// 536:1856: the closed "Expand Settings" bar.
    private static let closedCardHeight: CGFloat = 48
    /// The whole Subtitles tab content, unscrolled, through Appearance's Bold and Shadow rows.
    private static let appearanceHeight: CGFloat = 1280
    /// 800:1126 / 07m52.9 values: Inter (Figma) at #B8B8B8 with a #0C0C0C outline, no embedded styling.
    @MainActor private static func appearanceApp(_ mode: SubtitleSizeMode) -> AppModel {
        let app = sidebarApp()
        app.tracks.updateSubtitleStyle {
            $0.fontFamily = "Inter"; $0.textColor = MXRCore.RGBColor(vlcValue: 0xB8B8B8); $0.outlineColor = MXRCore.RGBColor(vlcValue: 0x0C0C0C)
            $0.useEmbeddedStyles = false; $0.sizeMode = mode
            if mode == .pixels { $0.pixelSize = 18; $0.outline = .thin }
        }
        return app
    }
    @MainActor private static func presetApp() -> AppModel {
        let app = sidebarApp()
        // 2372:8838 lists exactly these presets; replace the mock library's own.
        for preset in app.presets.customPresets { app.presets.delete(id: preset.id) }
        for name in ["Custom Preset 01", "Custom Preset 02", "Anime", "Loud and then Quiet Movies"] {
            app.presets.save(PlaybackPreset(name: name))
        }
        return app
    }
    @MainActor private static func sidebarApp() -> AppModel {
        let app = AppModel.mock(.playingEpisode)
        if let media = app.player.media { app.presets.assign(nil, to: media) }
        app.tracks.updateTrackDefaults { $0.audioTrack = 1; $0.audioLanguage = "English"; $0.subtitleTrack = 1; $0.subtitleLanguage = "English" }
        app.audioEffects.update { $0.stereoMode = .mono }
        return app
    }
}
