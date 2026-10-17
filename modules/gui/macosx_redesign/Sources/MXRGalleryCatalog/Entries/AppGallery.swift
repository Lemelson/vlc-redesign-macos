import AppKit
import SwiftUI
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI

/// Complete scenes exercise shared routing with the same composition used by VLC.
final class AppGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        [
            scene("S01.App/default", title: "Complete player", scenario: .playingEpisode,
                  node: "247:445", screens: ["S01"], canonicalTitle: true,
                  deviations: [.differs(node: "I491:1928;1908:7389", outset: 14, decision: "D048",
                                        "head at the labelled 00:02:10; Figma draws it at 00:01:53"),
                               .differs(node: "247:464", decision: "D022",
                                        "Figma's right group ends with Windows minimise, maximise and close; the Mac window keeps only the fullscreen button there")]),
            scene("S72.App/light", title: "Complete player · Light", scenario: .playingEpisode,
                  node: "2425:13624", screens: ["S72"], light: true, library: .compact,
                  deviations: [.differs(node: "I2425:13645;1908:7389", outset: 14, decision: "D048",
                                        "head at the labelled 00:02:10; Figma draws it at 00:01:53"),
                               .differs(node: "I2425:13645;3603:12304", decision: "D049",
                                        "Light accent fills use Light/Accent/Main; the frame's play button keeps Dark/Accent/Main"),
                               .differs(node: "2425:13640", decision: "D022",
                                        "Figma's right group ends with Windows minimise, maximise and close; the Mac window keeps only the fullscreen button there")]),
            scene("S43.App/home", title: "Full library", scenario: .idle,
                  node: "6261:15078", screens: ["S43"], library: .full),
            scene("S44.App/grid", title: "Full library · S01 grid", scenario: .idle,
                  node: "970:4028", screens: ["S44"], library: .full,
                  libraryLocation: .folder(MockMediaID.theWandS01Folder)),
            scene("S46.App/mini-player", title: "Full library with mini player", scenario: .pausedEpisode,
                  screens: ["S46"], library: .full),
            scene("S28.App/compact", title: "Compact library beside video", scenario: .pausedEpisode,
                  screens: ["S28"], library: .compact),
            scene("S14.App/subtitle-tracks", title: "Player with subtitle tracks", scenario: .playingEpisode,
                  screens: ["S14"], panel: .tracks(.subtitles)),
            scene("S20.App/subtitle-settings", title: "Player with subtitle preferences", scenario: .playingEpisode,
                  screens: ["S20"], panel: .sidebar(.subtitles)),
            scene("S22.App/queue", title: "Player with queue", scenario: .pausedEpisode,
                  screens: ["S22"], panel: .queue(.queue)),
            scene("S34.App/music", title: "Music with shared transport", scenario: .music,
                  node: "4767:23726", screens: ["S34"]),
            scene("S06.App/hidden", title: "Video only", scenario: .pausedEpisode,
                  node: "3328:11554", screens: ["S06"], hidden: true),
            scene("S66.App/customization", title: "Customization over the player", scenario: .playingEpisode,
                  node: "2107:5604", screens: ["S66"], customizing: true),
        ]
    }

    @MainActor
    private static func scene(_ id: String, title: String, scenario: MockBackend.Scenario,
                              node: String? = nil, screens: [String], light: Bool = false,
                              library: LibraryPresentation = .hidden, panel: RightPanel? = nil,
                              libraryLocation: LibraryLocation? = nil,
                              hidden: Bool = false, canonicalTitle: Bool = false, customizing: Bool = false,
                              deviations: [FigmaDeviation] = []) -> GalleryEntry {
        GalleryEntry(id: id, title: title, size: Theme.Metric.Window.player.size,
                     figmaNode: node, screens: screens, colorScheme: light ? .light : .dark,
                     notes: "Shipping composition with product defaults (D030), without the native titlebar; S*.Window entries and `--engine shipping-window` add it. Mock media imagery is isolated licensed Figma artwork.",
                     renderEngine: .hostingView, backdropMode: .liveMaterial, figmaDeviations: deviations) {
            // D030: product defaults; only the media fixture and the UI state differ per scene.
            let mock = MockBackend(scenario: scenario)
            let isIdleHome = scenario == .idle && (libraryLocation == nil || libraryLocation == .home)
            mock.thumbnails.usesFigmaHomeArtwork = isIdleHome
            mock.thumbnails.usesFigmaListArtwork = true
            if scenario == .music, mock.queue.items.count == 3 {
                let items = mock.queue.items.map(\.media)
                mock.queue.setItems([items[1], items[0], items[2]], current: 1)
            }
            // Player-6's media, the same fixture as S01.Window/shipping: with the product default
            // "Show the file name in the title bar" (D042) the title reads "VLC Media Player".
            if canonicalTitle { ShippingGallery.figmaPlayer6(mock) }
            let app = mock.makeAppModel()
            app.player.pause()
            app.player.setVolume(light ? 0.8 : 0.5)
            if customizing {
                if var media = mock.player.currentMedia {
                    media.episode?.episode = 11
                    media.duration = .hms(0, 25, 40)
                    mock.player.load(media, at: .hms(0, 2, 10), state: .paused)
                }
                // The empty second row of 2107:5604 is the product's edit-mode band (MXRControlBar).
                app.beginCustomizing()
            }
            if light { app.library.navigate(to: .folder(MockMediaID.theWandS01Folder)) }
            if let libraryLocation { app.library.navigate(to: libraryLocation) }
            app.interface.library = library
            app.interface.rightPanel = panel
            app.interface.isUIHidden = hidden
            app.appearance.setTheme(light ? .light : .dark)
            return ShippingGallery.host(app) {
                MXRAppView(videoView: scenario == .music ? AnyView(Color.clear) : PlayerGallery.catVideo())
            }
        }
    }
}
