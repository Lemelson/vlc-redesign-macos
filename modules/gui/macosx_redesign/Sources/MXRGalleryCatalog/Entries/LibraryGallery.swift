import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

final class LibraryGallery: NSObject, GalleryProvider {
    // Mini-player progress fill 970:3060 is 96pt, inside the 2pt track inset.
    private static let miniReferencePosition = Double((96 + Theme.Radius.xs * 2) / Theme.Metric.Miniplayer.videoBlock.width)
    @MainActor private static var miniVideo: AnyView {
        if let image = MockArtwork.image(named: "player-cat-canonical", maxPixelSize: CGSize(width: Theme.Metric.Miniplayer.videoBlock.width * 2, height: Theme.Metric.Miniplayer.videoBlock.height * 2)) {
            AnyView(Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill))
        } else { AnyView(Color.clear) }
    }

    /// Places the paused playhead where the Figma mini player draws it (970:3060). Titles, folder and
    /// artist chips come from the library data as in the shipping app (no caption overrides, L04).
    @MainActor private static func canonicalMini(_ app: AppModel) {
        guard let index = app.queue.currentIndex, app.queue.items.indices.contains(index) else { return }
        let current = app.queue.items[index].media
        (app.backends.player as? MockPlayer)?.load(current, at: (current.duration ?? app.clock.length) * miniReferencePosition, state: .paused)
    }

    /// The Figma mini player (970:3091) plays files named "The Wand_S01E11.mp4" … "The Wand_S01E14.mp4"
    /// (a space where the library frames have an underscore). The fixture queues files with those
    /// names, so the title and queue rows come from the media data like in the app (no caption
    /// override). `previous` queues E10 first, as the hover variant 975:4333 draws ⏮ enabled.
    @MainActor private static func figmaMini(_ app: AppModel, previous: Bool = false) {
        let episodes = (previous ? 10 : 11)...14
        let media: [MediaItem] = episodes.compactMap { episode in
            guard var item = (app.backends.library as? MockLibrary)?.mediaItem(id: MockMediaID.theWand(episode: episode)) else { return nil }
            let name = "The Wand_S01E\(episode).mp4"
            item.fileName = name
            item.title = name
            item.mrl = URL(fileURLWithPath: "/Users/Shared/Media/Videos/Shows/The Wand/S01/" + name).absoluteString
            return item
        }
        (app.backends.queue as? MockQueue)?.setItems(media, current: previous ? 1 : 0)
        canonicalMini(app)
    }

    /// D044: the artist chip is left out for media without an artist (Figma repeats "S01" there);
    /// the queue tools follow the queue (D044 amendment, 2026-10-17).
    private static func miniDeviations(artistChip: String, queueSummary: String? = nil, queueRemove: String? = nil) -> [FigmaDeviation] {
        [.differs(node: artistChip, decision: "D044", "no artist chip for a video without an artist (Figma repeats the folder name)")]
            + (queueSummary.map { [.differs(node: $0, outset: Theme.Spacing.gap8, decision: "D044", "queue length is the sum of the queued items (1h 34m), Figma's 2h 3m is a placeholder")] } ?? [])
            + (queueRemove.map { [.differs(node: $0, decision: "D044", "− (remove) is enabled only while queue rows are selected")] } ?? [])
    }

    @MainActor static func galleryEntries() -> [Any] {
        let compactWith: (String, String, LibraryLocation, String?, [FigmaDeviation]) -> GalleryEntry = { id, title, location, node, deviations in
            GalleryEntry(id: id, title: title, size: Theme.Metric.Library.sidebar.size,
                         figmaNode: node, screens: [String(id.prefix(3)), "S29", "S30", "S31", "S32", "S42"],
                         notes: "Interactive library: navigation, playback, sort/view/search, context menus, pins and add flows.", renderEngine: .hostingView,
                         figmaDeviations: deviations) {
                let app = AppModel.mock(id == "S28.Library/folder" ? .idle : .playingEpisode)
                (app.backends.thumbnails as? MockThumbnails)?.usesFigmaListArtwork = true
                // S40 (1106:5633) ranks three playlists Figma's Playlists page does not have and lists
                // the Videos entry points as its folders (gallery fixtures; the product ranks history).
                // The frame (like the 13m47 key frame) is reached by navigating, so ← is enabled.
                if id == "S40.Library/home" {
                    (app.backends.library as? MockLibrary)?.useFigmaHomePlaylists()
                    (app.backends.library as? MockLibrary)?.useFigmaHomeFolders()
                    app.library.navigate(to: .videos)
                }
                app.library.navigate(to: location)
                if location == .home { app.library.reload() }
                app.interface.library = .compact
                return MXRLibraryView(compact: true).appModel(app)
            }
        }
        let compact: (String, String, LibraryLocation, String?) -> GalleryEntry = { compactWith($0, $1, $2, $3, []) }
        // videos2 / videos3 repeat the Videos root's "3 items" over one and two folders.
        let ownCount: (String) -> [FigmaDeviation] = { node in
            [.differs(node: node, outset: Theme.Spacing.gap8, decision: "D044", "the count is the folder's own items; Figma repeats the Videos root's 3")]
        }
        let full: (String, String, LibraryLocation, LibraryViewMode, String?) -> GalleryEntry = { id, title, location, mode, node in
            GalleryEntry(id: id, title: title, size: CGSize(width: Theme.Metric.Window.player.width, height: Theme.Metric.Library.fullWindowNavColumn.height),
                         figmaNode: node, screens: [String(id.prefix(3)), "S42", "S47"],
                         notes: "Full library content beneath the common native window bar.", renderEngine: .hostingView,
                         figmaDeviations: id == "S45.Library/list" ? [
                            .differs(node: "1040:2612", outset: Theme.Spacing.gap8, decision: "D044", "the count is the folder's 15 items; Figma repeats Home's 110"),
                            // The docked card 970:3588 is a sibling of 970:3323, so its parts are placed by
                            // their render crops (title I970:3588;970:3064, chip I970:3588;970:3070) in entry points.
                            .differs(CGRect(x: 1531, y: 949, width: 196, height: 35), decision: "D044", "the mini player names the episode the list plays (E05, key frame 11m48.3); Figma's card says E04"),
                            .differs(CGRect(x: 1619, y: 994, width: 60, height: 24), decision: "D044", "no artist chip for a video without an artist"),
                         ] : []) {
                let app = AppModel.mock(id == "S45.Library/list" ? .playingEpisode : .idle)
                if location == .home { (app.backends.thumbnails as? MockThumbnails)?.usesFigmaHomeArtwork = true }
                app.library.navigate(to: location)
                if location == .home { app.library.reload() }
                app.library.fullViewMode = mode
                app.interface.library = .full
                if id == "S45.Library/list" {
                    (app.backends.thumbnails as? MockThumbnails)?.usesFigmaListArtwork = true
                    // Key frame 11m45.8s: E05 plays from the folder and the queue holds only it.
                    if let fifth = app.library.mediaEntries.first(where: { $0.episode?.episode == 5 }) {
                        (app.backends.queue as? MockQueue)?.setItems([fifth], current: 0)
                    }
                    canonicalMini(app)
                }
                return ZStack {
                    MXRLibraryView()
                    if id == "S45.Library/list" { MXRMiniPlayerDock(videoView: miniVideo) }
                }.appModel(app)
            }
        }
        return [
            GalleryEntry(id: "S29.LibraryMenu/file", title: "File context menu", size: CGSize(width: Theme.Metric.Menus.contextMenu.width, height: Theme.Metric.Menus.contextMenuRow.height * 12 + Theme.Spacing.gap4 * 2), figmaNode: "2404:13340", screens: ["S29"]) {
                let app = AppModel.mock(.pausedEpisode)
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                return MXRLibraryPopupView(kind: .file(app.player.media!)).appModel(app)
            },
            GalleryEntry(id: "S30.LibraryMenu/folder", title: "Folder context menu", size: Theme.Metric.Menus.contextMenu.size, figmaNode: "2139:8935", screens: ["S30"]) {
                let app = AppModel.mock(.playingEpisode)
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                return MXRLibraryPopupView(kind: .folder).appModel(app)
            },
            GalleryEntry(id: "S31.LibraryMenu/playlist", title: "Playlist context menu", size: CGSize(width: Theme.Metric.Menus.contextMenu.width, height: Theme.Metric.Menus.contextMenuRow.height * 8 + Theme.Spacing.gap4 * 2), figmaNode: "2459:9389", screens: ["S31"]) {
                let app = AppModel.mock(.idle)
                app.library.select(.playlists)
                let playlist = app.library.entries.compactMap { if case .playlist(let p) = $0 { return p }; return nil }.first!
                return MXRLibraryPopupView(kind: .playlist(playlist)).appModel(app)
            },
            GalleryEntry(id: "S32.LibraryMenu/sort", title: "Sorting Options", size: CGSize(width: Theme.Metric.Menus.contextMenu.width, height: Theme.Metric.Menus.contextMenuRow.height * CGFloat(LibrarySort.allCases.count) + Theme.Spacing.gap4 * 2), figmaNode: "856:2215", screens: ["S32"]) {
                let app = AppModel.mock(.idle)
                app.library.select(.videos)
                return MXRLibraryPopupView(kind: .sort, allSorts: true).appModel(app)
            },
            GalleryEntry(id: "S32.LibraryMenu/view", title: "View Options", size: CGSize(width: Theme.Metric.Menus.contextMenu.width, height: Theme.Metric.Menus.contextMenuRow.height * 2 + Theme.Spacing.gap4 * 2), figmaNode: "858:3290", screens: ["S32"]) {
                MXRLibraryPopupView(kind: .view(compact: true)).appModel(AppModel.mock(.idle))
            },
            compact("S28.Library/folder", "Compact library · S01", .folder(MockMediaID.theWandS01Folder), "848:1995"),
            // The Videos root and the folders above S01 (sidebar variants videos, videos2, videos3).
            compact("S28.Library/videos-root", "Compact library · Videos", .videos, "848:1997"),
            compactWith("S28.Library/shows", "Compact library · Videos ▸ Shows", .folder(MockMediaID.showsFolder), "4778:25847", ownCount("4778:25867")),
            compactWith("S28.Library/the-wand", "Compact library · Shows ▸ The Wand", .folder(MockMediaID.theWandFolder), "4778:25957", ownCount("4778:25977")),
            GalleryEntry(id: "S28.Library/narrow", title: "Compact library · Narrow panel", size: CGSize(width: Theme.Metric.Window.player.width / 2 * 0.32, height: Theme.Metric.Window.player.height / 2 - Theme.Metric.Window.topBar.height - Theme.Metric.ControlBar.bar.height), screens: ["S28"], renderEngine: .hostingView) {
                let app = AppModel.mock(.playingEpisode)
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                return MXRLibraryView(compact: true).appModel(app)
            },
            // The 480 pt minimum window gives the compact panel 45 % (216 pt): the header folds its
            // crumbs, then the count and Open Full Library, and draws inside the column.
            GalleryEntry(id: "S28.Library/minimum", title: "Compact library · Minimum window", size: CGSize(width: Theme.Metric.Window.player.width / 4 * 0.45, height: Theme.Metric.Window.player.height / 2 - Theme.Metric.Window.topBar.height - Theme.Metric.ControlBar.bar.height), screens: ["S28"], renderEngine: .hostingView) {
                let app = AppModel.mock(.playingEpisode)
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                return MXRLibraryView(compact: true).appModel(app)
            },
            compact("S33.Library/music", "Compact library · Music", .music, "858:5001"),
            compact("S33.Library/songs", "Compact library · Songs", .songs, "4767:23606"),
            compact("S33.Library/my-songs", "Compact library · My Songs", .folder(MockMediaID.mySongsFolder), "4778:24990"),
            compact("S33.Library/albums", "Compact library · Albums", .albums, nil),
            compact("S33.Library/artists", "Compact library · Artists", .artists, nil),
            compact("S33.Library/genres", "Compact library · Genres", .genres, nil),
            compact("S35.Library/network", "Compact library · Network", .network, "858:5294"),
            GalleryEntry(id: "S35.Library/sources", title: "Network · Live source browser", size: CGSize(width: Theme.Metric.Library.sidebar.width, height: Theme.Metric.Miniplayer.queue.height), screens: ["S35"], renderEngine: .hostingView) {
                MXRMediaSourcesView().appModel(AppModel.mock(.idle))
            },
            compact("S38.Library/playlists", "Compact library · Playlists", .playlists, "858:5374"),
            compact("S40.Library/home", "Compact library · Home", .home, "1106:5633"),
            compact("S41.Library/recent", "Compact library · Recent", .recent, nil),
            full("S43.Library/home", "Full library · Home", .home, .grid, "6261:15093"),
            full("S44.Library/grid", "Full library · S01 grid", .folder(MockMediaID.theWandS01Folder), .grid, "970:4043"),
            full("S45.Library/list", "Full library · S01 list", .folder(MockMediaID.theWandS01Folder), .list, "970:3323"),
            GalleryEntry(id: "S44.Library/narrow", title: "Full library · Narrow window", size: CGSize(width: Theme.Metric.Window.player.width / 4, height: Theme.Metric.Window.player.height / 2), screens: ["S44"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                return MXRLibraryView().appModel(app)
            },
            GalleryEntry(id: "S46.MiniPlayer/collapsed", title: "Mini player", size: Theme.Metric.Miniplayer.collapsed.size,
                         figmaNode: "970:3090", screens: ["S46"], renderEngine: .hostingView,
                         figmaDeviations: miniDeviations(artistChip: "970:3070")) {
                let app = AppModel.mock(.pausedEpisode)
                figmaMini(app)
                return MXRMiniPlayerView(videoView: miniVideo).appModel(app)
            },
            GalleryEntry(id: "S46.MiniPlayer/music-artist", title: "Mini player · Music artist", size: Theme.Metric.Miniplayer.collapsed.size,
                         screens: ["S46"], notes: "Semantic fixture: artist chip appears only when real media metadata supplies an artist. Not a Figma caption override.", renderEngine: .hostingView) {
                let app = AppModel.mock(.music)
                return MXRMiniPlayerView().appModel(app)
            },
            GalleryEntry(id: "S46.MiniPlayer/queue", title: "Mini player · Expanded queue", size: Theme.Metric.Miniplayer.expanded.size,
                         figmaNode: "970:3092", screens: ["S46"], renderEngine: .hostingView,
                         figmaDeviations: miniDeviations(artistChip: "970:3108", queueSummary: "970:3189", queueRemove: "970:3192")) {
                let app = AppModel.mock(.pausedEpisode)
                figmaMini(app)
                app.interface.isMiniPlayerQueueExpanded = true
                return MXRMiniPlayerView(videoView: miniVideo).appModel(app)
            },
            GalleryEntry(id: "S46.MiniPlayer/short-window", title: "Mini player · Queue in a short window", size: CGSize(width: Theme.Metric.Window.player.width / 2, height: Theme.Metric.Window.player.height / 2 - Theme.Metric.Window.topBar.height), screens: ["S46"], renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.interface.isMiniPlayerQueueExpanded = true
                return MXRMiniPlayerDock(videoView: miniVideo).appModel(app)
            },
            GalleryEntry(id: "S47.Library/search", title: "Library · Search results", size: CGSize(width: Theme.Metric.Window.player.width, height: Theme.Metric.Library.fullWindowNavColumn.height), screens: ["S47"], renderEngine: .hostingView) {
                let app = AppModel.mock(.idle)
                app.library.searchText = "untangle"
                app.library.reload()
                return MXRLibraryView().appModel(app)
            },
            GalleryEntry(id: "S43.Library/empty", title: "Library · Empty", size: CGSize(width: Theme.Metric.Window.player.width, height: Theme.Metric.Library.fullWindowNavColumn.height), screens: ["S43"], renderEngine: .hostingView) {
                MXRLibraryView().appModel(AppModel.mock(.emptyLibrary))
            },
            GalleryEntry(id: "S28.Library/empty-videos", title: "Compact library · No video folders", size: Theme.Metric.Library.sidebar.size, screens: ["S28"],
                         notes: "First launch: Videos has no entry points; the + Add row and the design-system empty state guide to Add Folder.", renderEngine: .hostingView) {
                let app = AppModel.mock(.emptyLibrary)
                app.library.select(.videos)
                return MXRLibraryView(compact: true).appModel(app)
            },
            GalleryEntry(id: "S35.Library/network-first-launch", title: "Compact library · Network defaults", size: Theme.Metric.Library.sidebar.size, screens: ["S35"],
                         notes: "First launch: the seeded Podcasts and Radio collections (VIDEO_BREAKDOWN §10).", renderEngine: .hostingView) {
                let app = AppModel.mock(.emptyLibrary)
                app.library.select(.network)
                return MXRLibraryView(compact: true).appModel(app)
            },
            GalleryEntry(id: "S28.Library/hover", title: "Compact library · Row hover", size: Theme.Metric.Library.sidebar.size,
                         screens: ["S28"], notes: "Hovered row E06: FG/2 label and the ⋯ button (compare the row with media hover 2404:9168).", renderEngine: .hostingView) {
                let app = AppModel.mock(.playingEpisode)
                (app.backends.thumbnails as? MockThumbnails)?.usesFigmaListArtwork = true
                app.library.navigate(to: .folder(MockMediaID.theWandS01Folder))
                return MXRLibraryView(compact: true).mxrLibraryPreviewHover("media:ml:wand-s01e06").appModel(app)
            },
            GalleryEntry(id: "S46.MiniPlayer/hover", title: "Mini player · Hover", size: Theme.Metric.Miniplayer.collapsed.size,
                         figmaNode: "975:4333", screens: ["S46"], renderEngine: .hostingView,
                         figmaDeviations: miniDeviations(artistChip: "975:4352")) {
                let app = AppModel.mock(.pausedEpisode)
                figmaMini(app, previous: true)
                return MXRMiniPlayerView(videoView: miniVideo).mxrLibraryPreviewHover(MXRLibraryPreview.miniPlayer).appModel(app)
            },
        ]
    }
}
