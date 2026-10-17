import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// Figma geometry not yet present in the shared generated metric catalog.
enum LibraryGeometry {
    // Full library content/header nodes 970:3344, 1040:2605, 1040:2611.
    static let fullHeaderHeight: CGFloat = 34
    static let collapsedBreadcrumbWidth: CGFloat = 14 // Ellipsis slot 6131:13764; 6pt gap in 6131:13763.
    static let crumbSeparatorWidth: CGFloat = 8 // "▶" text box 6153:13644 (the glyph itself draws 7.5 pt).
    static let searchWidth: CGFloat = 325 // 1040:2864 / 1040:2876 / 6261:15136.
    /// The compact panel's header with every tool (848:1874: ← → … ⋯ open), crumbs folded to "…".
    static var compactFullHeaderWidth: CGFloat {
        let library = Theme.Metric.Library.self
        return library.rail.width + library.panel.padding.leading + library.panel.padding.trailing
            + 4 * Theme.Metric.iconSize + 2 * Theme.Spacing.gap12 + 2 * library.headerRow.gap + collapsedBreadcrumbWidth
    }
    /// Narrower than ``compactFullHeaderWidth`` the panel leaves out Open Full Library (View ▸ Go Home
    /// still opens it); this is the narrowest compact panel that draws inside its column.
    static var compactMinimumWidth: CGFloat { compactFullHeaderWidth - Theme.Metric.iconSize - Theme.Spacing.gap12 }
    // Full library grid tile 970:4081, Home music/folder cards 6272:13899 / 6284:13942.
    static let squareCard: CGFloat = 200
    static let gridTitleGap: CGFloat = 20
    static let gridRowGap: CGFloat = 40
    static let fullListRowWidth: CGFloat = 406 // S45 6841:15992, rows x237/653/1069/1485 with 10pt gaps.
    // Full Home sections use 20pt internal padding and the content column's 17pt gap.
    static let homeSectionGap: CGFloat = 17
    static let cardCaptionHeight: CGFloat = 19 // 6270:13769 and 6272:13901.
    // Compact Home sections 1107:5920 / 1107:5921.
    static let compactSectionGap: CGFloat = 30
    static let compactHeadingGap: CGFloat = 15
    // Thumbnail progress line and mini seek bar 970:3059.
    static let progressHeight: CGFloat = 3
    static let miniSeekHeight: CGFloat = 16
    static let miniExpandedVideoBlock: CGFloat = 229.6875 // 970:3093; child media remains375×210.9375.
    // Mini player hover overlay 975:4335: 42.86pt transport icons in 53.57×50 cells (975:4337/4339),
    // spaced ≈27pt; playhead Rectangle 10 (975:4511) is 8×12.
    static let miniTransportIcon: CGFloat = 42.857
    static let miniTransportCell = CGSize(width: 53.571, height: 50)
    static let miniTransportGap: CGFloat = Theme.Spacing.gap27
    /// Centre of ⏮ ▶ ⏭ (975:4337…975:4339) in the 375×210.94 video 975:4335: 0.7 pt left of and
    /// 1.5 pt above the video centre. Scaled with the video when the window makes it smaller.
    static let miniTransportCenter = CGPoint(x: 186.785, y: 104)
    /// The mini player's video (970:3056, 975:4335): the video block's full width at 16:9,
    /// 375×210.94 pt; the 16 pt seek row sits 4 pt below it.
    static let miniVideoAspect: CGFloat = 16 / 9
    static var miniVideoSize: CGSize {
        CGSize(width: Theme.Metric.Miniplayer.videoBlock.width, height: Theme.Metric.Miniplayer.videoBlock.width / miniVideoAspect)
    }
    static let miniPlayheadWidth: CGFloat = 8
    // Full library art 970:4081 and folder tile 6284:13942.
    static let gridRadius: CGFloat = 12
    static let tileIcon: CGFloat = 48
}

private struct LibraryPreviewHoverKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    /// Gallery state previews: the id of the library entry drawn as hovered, or ``MXRLibraryPreview/miniPlayer``.
    var mxrLibraryPreviewHover: String? {
        get { self[LibraryPreviewHoverKey.self] }
        set { self[LibraryPreviewHoverKey.self] = newValue }
    }
}

/// Hover is pointer state; the gallery renders it explicitly to compare with the Figma hover variants
/// (media 2404:9168/2404:9256, Miniplayer 975:4333).
public enum MXRLibraryPreview {
    public static let miniPlayer = "mini-player"
}

public extension View {
    /// Draws the library entry `entryID` (or the mini player) in its hover state. Gallery only.
    func mxrLibraryPreviewHover(_ entryID: String?) -> some View { environment(\.mxrLibraryPreviewHover, entryID) }
}

enum LibraryPaint {
    // Selected list thumbnail fill I6841:15992;2404:9180;2404:9199.
    static let currentShade = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.7)
    static let currentTint = Color(.sRGB, red: 0.5853928924, green: 0.5025610328, blue: 0.4132864177, opacity: 0.2)
    // Mini player hover scrim over the video, third fill of 975:4335 (#000000 @ 0.6).
    static let miniHoverScrim = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 0.6)
}

@MainActor
enum MXRLibraryActions {
    /// Edit / Add Audio Tracks for a folder or playlist: its videos take the chosen audio files
    /// whose names match theirs (``LibraryAudioTracks``). Songs are left out, as in Add Subtitles.
    static func addAudioTracks(to media: [MediaItem], place: String, app: AppModel) {
        let videos = media.filter { $0.kind != .audio }
        guard !videos.isEmpty else {
            app.dialogs.presentError(BackendOperationError.invalidInput("There are no videos in this \(place)."), title: "No Audio Tracks to Add")
            return
        }
        app.presentAddAudioTracks(media: videos)
    }

    /// The row shows the now-playing state when its media is the player's current media.
    static func isCurrentMedia(_ media: MediaItem, app: AppModel) -> Bool {
        guard let current = app.player.media else { return false }
        return current.id == media.id || sameResource(current.mrl, media.mrl)
    }

    static func sameResource(_ a: String, _ b: String) -> Bool {
        guard a != b else { return true }
        guard let left = URL(string: a), let right = URL(string: b) else { return false }
        return (left.isFileURL ? left.standardizedFileURL : left.standardized) == (right.isFileURL ? right.standardizedFileURL : right.standardized)
    }

    /// Double-click / Return / "Play": containers open, media play.
    static func open(_ entry: LibraryEntry, app: AppModel) {
        if let media = app.library.open(entry) { play([media], app: app) }
    }

    /// Plays `media` without discarding the queue (PHILOSOPHY §3.7, key frames 11m45.8s/11m57.0s: playing
    /// E05 from a 15-item folder leaves "1 item" in the queue; the user builds the rest by dragging).
    /// The first item replaces the current one, further items follow it, upcoming items are kept.
    /// An item that is already queued is simply jumped to.
    static func play(_ media: [MediaItem], app: AppModel) {
        let queue = app.queue
        guard let first = media.first else { return }
        if media.count == 1, let queued = queue.items.first(where: { $0.media.id == first.id || sameResource($0.media.mrl, first.mrl) }) {
            if queue.isCurrent(queued) { if !app.player.isPlaying { app.player.togglePlayPause() } }
            else { queue.play(queued) }
            return
        }
        guard let current = queue.currentIndex, queue.items.indices.contains(current) else {
            if queue.items.isEmpty { queue.playNow(media) }
            else {
                queue.insert(media, at: 0)
                if let inserted = queue.items.first { queue.play(inserted) }
            }
            return
        }
        let replaced = queue.items[current].id
        queue.insert(media, at: current + 1)
        guard queue.items.indices.contains(current + 1) else { return }
        queue.play(queue.items[current + 1])
        queue.remove([replaced])
    }

    static func add(_ action: LibraryAddAction, app: AppModel) {
        switch action {
        case .add: app.interface.request(.addLibraryFolder)
        case .addNetworkStream: app.interface.present(.openNetworkStream)
        case .createPlaylist: app.presentNewPlaylist(media: [])
        }
    }

    static func media(for entry: LibraryEntry, app: AppModel) async -> [MediaItem] {
        if let media = entry.media { return [media] }
        if let location = entry.destination { return await app.library.allMedia(at: location) }
        if case .stream(let stream) = entry { return stream.urls.map { url in
            var media = MediaItem(url: url); media.title = stream.name; return media
        } }
        return []
    }

    /// The media an action on `entry` applies to: the whole selection when the row is part of it.
    static func media(forSelectionContaining entry: LibraryEntry, app: AppModel) async -> [MediaItem] {
        let library = app.library
        if library.selection.count > 1, library.selection.contains(entry.id) {
            var result: [MediaItem] = []
            for selected in library.entries where library.selection.contains(selected.id) {
                result += await media(for: selected, app: app)
            }
            return result
        }
        return await media(for: entry, app: app)
    }

    static func enqueue(_ entry: LibraryEntry, app: AppModel, next: Bool) async {
        let media = await media(forSelectionContaining: entry, app: app)
        if next { app.queue.playNext(media) } else { app.queue.enqueue(media) }
    }

    /// "Play" on a folder, playlist, album or stream: the whole container, in library order.
    static func playContainer(_ entry: LibraryEntry, app: AppModel) async {
        let media = await media(for: entry, app: app)
        if !media.isEmpty { app.queue.playNow(media) }
    }

    static func shuffleContainer(_ entry: LibraryEntry, app: AppModel) async {
        await playContainer(entry, app: app)
        if !app.queue.isShuffled { app.queue.toggleShuffle() }
    }

    static func newPlaylist(for entry: LibraryEntry, app: AppModel) async {
        app.presentNewPlaylist(media: await media(forSelectionContaining: entry, app: app))
    }

    static func addSubtitles(for entry: LibraryEntry, scope: AddSubtitlesScope, app: AppModel) async {
        app.presentAddSubtitles(media: await media(for: entry, app: app), scope: scope)
    }
}

/// Library empty, error and info states in the design system: icon, FG/A1 title, FG/A3 hint and a
/// Figma Button (500:3063) for the next step (PHILOSOPHY §3.9 "Use your words").
struct LibraryMessage: View {
    let icon: MXRIcon.Name
    let title: String
    var hint: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.gap10) {
            MXRIcon(icon, size: LibraryGeometry.tileIcon, tint: Theme.Color.fgA3)
                .padding(.bottom, Theme.Spacing.gap10)
            Text(title).mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA1)
                .multilineTextAlignment(.center)
            if let hint {
                Text(hint).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle, let action {
                DialogButton(title: actionTitle, primary: true, action: action).padding(.top, Theme.Spacing.gap10)
            }
        }
        .padding(.horizontal, Theme.Spacing.gap20)
        .frame(maxWidth: .infinity)
        .padding(.vertical, LibraryGeometry.gridRowGap)
        .accessibilityElement(children: .contain)
    }
}

extension LibraryCategory {
    var mxrIcon: MXRIcon.Name {
        switch self {
        case .home: .home
        case .videos: .videos
        case .music: .songs
        case .network: .streaming
        case .playlists: .playlist
        case .recent: .recent
        }
    }
}

extension LibraryEntry {
    var mxrIcon: MXRIcon.Name {
        switch self {
        case .media(let media): media.kind == .audio ? .music : .video
        // Figma draws every folder (music ones too: My Songs in 4767:23606 and 6261:15093) with the plain folder glyph.
        case .folder: .folder
        case .playlist: .playlist
        case .album: .album
        case .artist: .artist
        case .genre: .genre
        case .show: .videos
        case .stream: .streaming
        case .link(let link): MXRIcon.Name(rawValue: link.iconName) ?? .folder
        }
    }

    var mxrSubtitle: String? {
        switch self {
        case .media(let media): media.artist
        case .folder(let folder): folder.itemCount.map { "\($0) items" }
        case .playlist(let playlist): "\(playlist.itemCount) items"
        case .album(let album): [album.artist, album.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        case .artist(let artist): "\(artist.albumCount) albums · \(artist.trackCount) tracks"
        case .genre(let genre): "\(genre.trackCount) tracks"
        case .show(let show): "\(show.seasonCount) seasons"
        case .stream(let stream): stream.itemCount.map { "\($0) items" }
        case .link: nil
        }
    }

    var mxrArtworkMedia: MediaItem? {
        if let media { return media }
        let url: URL? = switch self {
        case .album(let value): value.artworkURL
        case .artist(let value): value.artworkURL
        case .playlist(let value): value.artworkURL
        case .show(let value): value.artworkURL
        default: nil
        }
        guard let url else { return nil }
        return MediaItem(id: id, mrl: url.absoluteString, title: title, kind: .unknown, artworkURL: url)
    }

    var mxrPinTarget: PinTarget? {
        if let media { return .media(media) }
        return destination.map(PinTarget.location)
    }
}

struct LibraryIconButton: View {
    let icon: MXRIcon.Name
    let label: String
    var active = false
    var enabled = true
    /// Navigation arrows, row ⋯ and the queue toggle are FG/A2 (2404:9168, 970:3073); the tools of a
    /// library header and of the queue (sort, view, search, ⋯, add, open: 1106:5633, 970:3190) are FG/A3.
    var tool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            MXRIcon(icon, state: active ? .active : .default,
                    tint: enabled ? (tool ? Theme.Color.fgA3 : Theme.Color.fgA2) : Theme.Color.fgA4)
                .frame(width: Theme.Metric.iconSize, height: Theme.Metric.iconSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .background { if hovered { RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.Color.iconHover) } }
        .onHover { hovered = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

struct LibraryDivider: View {
    /// The divider under the library header (Dark/Divider/Dim in Player - Light too, see
    /// `libraryHeaderDarkStyle`).
    var header = false
    var body: some View {
        Color.clear.frame(height: 0).overlay {
            if header { line.libraryHeaderDarkStyle() } else { line }
        }
    }
    private var line: some View { Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.hairline) }
}

/// Uses the backend's synchronous cache for the first frame, then requests art asynchronously.
struct LibraryArtwork: View {
    @Environment(AppModel.self) private var app
    let entry: LibraryEntry
    let size: CGSize
    var radius: CGFloat = Theme.Radius.xs
    var isCurrent = false
    var large = false
    var showProgress = true
    @State private var loaded: CGImage?

    private struct ArtworkRequest: Hashable {
        let media: MediaItem?
        let width: Int
        let height: Int
    }
    private var pixels: CGSize {
        let native = entry.media?.videoSize
        let aspect = native.flatMap { size -> CGFloat? in
            guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
            return size.width / size.height
        } ?? (entry.media?.kind == .video ? Theme.Metric.Library.homeCard.width / Theme.Metric.Library.homeCard.height : 1)
        if size.width / max(size.height, 1) > aspect { return CGSize(width: size.width * 2, height: size.width * 2 / aspect) }
        return CGSize(width: size.height * 2 * aspect, height: size.height * 2)
    }
    private var cached: CGImage? {
        entry.mxrArtworkMedia.flatMap { app.backends.thumbnails.cachedArtwork(for: $0, maxPixelSize: pixels) }
    }

    var body: some View {
        ZStack {
            if let image = loaded ?? cached {
                Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(large ? Theme.Color.bgA2 : Theme.Color.thumbPlaceholder)
                MXRIcon(entry.mxrIcon, size: large ? LibraryGeometry.tileIcon : Theme.Metric.iconSize)
            }
            if isCurrent {
                Rectangle().fill(LibraryPaint.currentShade)
                Rectangle().fill(LibraryPaint.currentTint)
                // Source current-row overlay 6841:16007 uses outline icon 999:4802.
                MXRIcon(.playback, tint: Theme.Color.accentMain)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if entry.media?.kind == .video, let progress = entry.media?.displayProgress,
               showProgress || entry.media?.isWatched == true {
                Rectangle().fill(Theme.Color.accentMain)
                    .frame(width: max(0, size.width - (large ? 0 : Theme.Spacing.gap4)) * min(max(progress, 0), 1),
                           height: large ? Theme.Spacing.gap4 : LibraryGeometry.progressHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .task(id: ArtworkRequest(media: entry.mxrArtworkMedia, width: Int(pixels.width), height: Int(pixels.height))) {
            loaded = nil
            if let media = entry.mxrArtworkMedia {
                let image = await app.backends.thumbnails.artwork(for: media, maxPixelSize: pixels)
                if !Task.isCancelled { loaded = image }
            }
        }
        .accessibilityHidden(true)
    }
}
