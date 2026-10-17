import AppKit
import MXRCore
import MXRDesign
import MXRMockBackend
import MXRUI
import SwiftUI

final class DialogsGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let subtitleBox = Theme.Metric.Dialogs.addSubtitles
        let episodes = (1...15).map { index -> MediaItem in
            let name = String(format: "The_Wand_S01E%02d.mp4", index)
            return MediaItem(id: "dialog-episode-\(index)", mrl: "file:///Movies/\(name)", title: name, fileName: name, kind: .video)
        }
        let batch = episodes.map { URL(fileURLWithPath: "/Subtitles/" + ($0.listTitle as NSString).deletingPathExtension + ".srt") }
        let languages = ["English", "Spanish", "Japanese", "German", "Dutch", "French"].map { URL(fileURLWithPath: "/Subtitles/The_Wand_S01E01_\($0).srt") }
        return [
            GalleryEntry(id: "S25.App/add-subtitles", title: "Add Subtitles over the player (shipping composition)",
                         size: Theme.Metric.Window.player.size, screens: ["S25"],
                         notes: "SD-11: one centred dialog; the player and bars stay at full brightness, as at 06m02.5 (D035).", renderEngine: .hostingView) {
                let app = AppModel.mock(.playingEpisode)
                app.interface.present(.addSubtitles(scope: .file, source: .computer))
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S37.App/convert-compact", title: "Convert in a 960 × 540 window", size: CGSize(width: 960, height: 540),
                         screens: ["S37"], notes: "The form keeps its size and scrolls instead of being scaled.", renderEngine: .hostingView) {
                let app = AppModel.mock(.pausedEpisode)
                app.interface.present(.convert)
                return ShippingGallery.host(app) { MXRAppView(videoView: PlayerGallery.catVideo(windowSize: CGSize(width: 960, height: 540)), onPictureInPicture: {}) }
            },
            GalleryEntry(id: "S25.AddSubtitles/folder", title: "Add subtitles to folder", size: subtitleBox.size,
                         figmaNode: "1911:7545", screens: ["S25"], renderEngine: .hostingView) {
                MXRAddSubtitlesView(scope: .folder, source: .computer, media: episodes, subtitles: batch,
                                    locationTitle: "Videos / Shows / The Wand / S01").appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S26.AddSubtitles/file", title: "Add subtitle language files", size: subtitleBox.size,
                         figmaNode: "1919:8707", screens: ["S26"], renderEngine: .hostingView) {
                MXRAddSubtitlesView(scope: .file, source: .computer, media: [episodes[0]], subtitles: languages,
                                    selected: Set(languages.prefix(2)), locationTitle: "Videos / Shows / The Wand / S01")
                    .appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S27.AddSubtitles/unavailable", title: "OpenSubtitles unavailable", size: subtitleBox.size,
                         screens: ["S27"], notes: "No API key or search backend is configured; the service is never simulated as successful.", renderEngine: .hostingView) {
                MXRAddSubtitlesView(scope: .file, source: .openSubtitles).appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S27.AddSubtitles/results", title: "OpenSubtitles supplied results", size: subtitleBox.size,
                         figmaNode: "1919:9278", screens: ["S27"],
                         notes: "Offline gallery fixture with supplied files; the production search service remains unavailable.", renderEngine: .hostingView) {
                let results = [languages[0], URL(fileURLWithPath: "/Subtitles/The_Wand_S01E01_EN.srt")]
                return MXRAddSubtitlesView(scope: .file, source: .openSubtitles, media: [episodes[0]], subtitles: results,
                                          selected: [results[0]], search: "The Wand S01E01").appModel(AppModel.mock(.playingEpisode))
            },
            GalleryEntry(id: "S36.NetworkStream/empty", title: "Open Network Stream", size: Theme.Metric.Dialogs.openNetworkStream.size,
                         figmaNode: "6216:13614", screens: ["S36"], renderEngine: .hostingView) {
                MXRNetworkStreamView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S36.NetworkStream/valid", title: "Save network playlist", size: Theme.Metric.Dialogs.openNetworkStream.size,
                         screens: ["S36"], renderEngine: .hostingView) {
                MXRNetworkStreamView(urls: "https://example.com/channels.m3u", name: "Favorite TV Channels").appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S39.NewPlaylist/empty", title: "New Playlist", size: Theme.Metric.Dialogs.newPlaylist.size,
                         figmaNode: "6259:14954", screens: ["S39"], renderEngine: .hostingView) {
                MXRNewPlaylistView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S37.Disc/empty", title: "Open Disc", size: MXRDiscView.preferredSize, screens: ["S37"], renderEngine: .hostingView) {
                MXRDiscView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S37.Capture/empty", title: "Open Capture Device", size: MXRCaptureView.preferredSize, screens: ["S37"], renderEngine: .hostingView) {
                MXRCaptureView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S37.Convert/empty", title: "Convert", size: Theme.Metric.Dialogs.newPlaylist.size, screens: ["S37"], renderEngine: .hostingView) {
                MXRConvertView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S37.Stream/empty", title: "Stream", size: MXRStreamView.preferredSize, screens: ["S37"], renderEngine: .hostingView) {
                MXRStreamView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S37.Convert/running", title: "Convert while converting", size: Theme.Metric.Dialogs.newPlaylist.size, screens: ["S37"],
                         notes: "The Save As row shows the progress; the form is locked and the main button stops the job.", renderEngine: .hostingView) {
                let mock = MockBackend(scenario: .idle)
                mock.output.add(OutputJob(id: "gallery-convert", sourceURL: URL(fileURLWithPath: "/Movies/The_Wand_S01E04.mkv"),
                                          destinationURL: URL(fileURLWithPath: "/Movies/The_Wand_S01E04.mp4"), mode: .convert,
                                          profile: "h264", state: .running, progress: 0.42))
                return MXRConvertView().appModel(mock.makeAppModel())
            },
            GalleryEntry(id: "S37.Stream/running", title: "Stream while streaming", size: MXRStreamView.preferredSize, screens: ["S37"],
                         notes: "The Send To hint says where other devices open the stream.", renderEngine: .hostingView) {
                let mock = MockBackend(scenario: .idle)
                mock.output.add(OutputJob(id: "gallery-stream", sourceURL: URL(fileURLWithPath: "/Movies/The_Wand_S01E04.mkv"),
                                          destinationURL: URL(string: "http://0.0.0.0:8080/live"), mode: .stream,
                                          profile: "copy", state: .running, progress: 0.1))
                return MXRStreamView().appModel(mock.makeAppModel())
            },
            GalleryEntry(id: "S65.About/default", title: "About VLC Redesign", size: Theme.Metric.Dialogs.newPlaylist.size, screens: ["S65"], renderEngine: .hostingView) {
                MXRAboutView().appModel(AppModel.mock(.idle))
            },
            GalleryEntry(id: "S65.MediaInfo/episode", title: "Properties & Metadata", size: MXRMediaInfoView.maximumSize, screens: ["S65"], renderEngine: .hostingView) {
                let app = AppModel.mock(.playingEpisode)
                return MXRMediaInfoView(media: app.player.media!).appModel(app)
            },
        ]
    }
}
