import AppKit
import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

public enum MXRLibraryPopupKind {
    case add
    case sort
    case view(compact: Bool)
    /// The header ⋯ of the shown folder (Figma folder context menu 2139:8935).
    case folder
    case folderEntry(LibraryFolder)
    case file(MediaItem)
    case playlist(Playlist)
    case stream(NetworkStream)
    /// Albums, artists, genres, shows and links.
    case collection(LibraryEntry)
}

/// One row of a library menu. The ⋯ card and the right-click menu are both generated from
/// ``LibraryMenus`` so they offer the same actions in the same (Figma) order.
struct LibraryMenuItem: Identifiable {
    enum Kind {
        case perform(@MainActor () -> Void)
        /// Opens the playlist chooser (⋯ card) or the "Add to Playlist" submenu (right-click).
        case addToPlaylist([MediaItem]?, LibraryEntry?)
    }
    var id: String { title }
    let title: String
    let icon: MXRIcon.Name
    /// Figma's file menu draws Mark as Watched with the two-tone `check` state=selected (4004:12348).
    var iconState: MXRIcon.State = .default
    var enabled = true
    var selected = false
    var help: String?
    let kind: Kind
}

/// Item lists per entry kind. `figma` rows are the design's menus (file 2404:13340, playlist 2459:9389);
/// `extras` are Mac conveniences that only the right-click menu adds (Play Next, Pin, Rename, Remove).
@MainActor
enum LibraryMenus {
    struct Sections {
        var figma: [LibraryMenuItem]
        var extras: [LibraryMenuItem] = []
    }

    static func sections(for kind: MXRLibraryPopupKind, app: AppModel, sheets: LibrarySheetCenter?,
                         rowIndex: Int?, dismiss: @escaping @MainActor () -> Void) -> Sections {
        func item(_ title: String, _ icon: MXRIcon.Name, iconState: MXRIcon.State = .default, enabled: Bool = true, selected: Bool = false,
                  help: String? = nil, _ action: @escaping @MainActor () -> Void) -> LibraryMenuItem {
            LibraryMenuItem(title: title, icon: icon, iconState: iconState, enabled: enabled, selected: selected, help: help,
                            kind: .perform { action(); dismiss() })
        }
        func async(_ title: String, _ icon: MXRIcon.Name, enabled: Bool = true, _ action: @escaping @MainActor () async -> Void) -> LibraryMenuItem {
            LibraryMenuItem(title: title, icon: icon, enabled: enabled, kind: .perform { dismiss(); Task { await action() } })
        }
        func pin(_ entry: LibraryEntry) -> LibraryMenuItem? {
            guard let target = entry.mxrPinTarget else { return nil }
            let pinned = app.pins.isPinned(target)
            return item(pinned ? "Unpin" : "Pin to Sidebar", .favorite, selected: pinned) {
                if pinned { app.pins.unpin(target) } else { app.pins.pin(entry) }
            }
        }
        func info(_ title: String, _ lines: [String]) -> LibraryMenuItem {
            item("Properties & Metadata", .info) { sheets?.present(.info(title: title, lines: lines)) }
        }

        switch kind {
        case .add:
            return Sections(figma: [
                item("Pin \(app.library.title)", .favorite) { app.pins.pin(.location(app.library.location), title: app.library.title) },
                item("Add Folder", .newFolder) { app.interface.request(.addLibraryFolder) },
                item("Add Network Stream", .streaming) { app.interface.present(.openNetworkStream) },
                item("Create Playlist", .playlist) { app.presentNewPlaylist(media: []) },
            ])
        case .sort, .view:
            return Sections(figma: [])
        case .folder:
            let location = app.library.location
            let isFolder: Bool = { if case .folder = location { return true }; return false }()
            return Sections(figma: [
                // Figma's label; the files join the library (not this folder) and the library then shows them
                // selected under Videos or Music ▸ Songs (LibraryModel.importFiles).
                item("Add File", .add, help: "Add files to the library. They appear under Videos or Music.") { app.interface.request(.addLibraryFiles) },
                item("Add Folder", .newFolder) { app.interface.request(.addLibraryFolder) },
                async("Edit Subtitle Tracks", .subtitles, enabled: isFolder) {
                    app.presentAddSubtitles(media: await app.library.allMedia(at: location), scope: .folder)
                },
                async("Edit Audio Tracks", .audio, enabled: isFolder) {
                    MXRLibraryActions.addAudioTracks(to: await app.library.allMedia(at: location), place: "folder", app: app)
                },
                item("Resync", .refresh) { if case .folder(let id) = location { app.library.rescan(id) } else { app.library.rescan() } },
                item("Info", .info) {
                    sheets?.present(.info(title: app.library.title, lines: [app.library.countText]
                        + (app.library.breadcrumb.count > 1 ? [app.library.breadcrumb.map(\.title).joined(separator: " ▸ ")] : [])))
                },
            ])
        case .file(let media):
            let entry = LibraryEntry.media(media)
            let local = URL(string: media.mrl).map(\.isFileURL) ?? false
            var figma = [
                async("Play", .playback) { MXRLibraryActions.play(await MXRLibraryActions.media(forSelectionContaining: entry, app: app), app: app) },
                item(media.isWatched ? "Mark as Unwatched" : "Mark as Watched", .check, iconState: .selected) {
                    let targets = app.library.selection.contains(entry.id) ? app.library.selectedMedia : [media]
                    app.library.setWatched(!media.isWatched, for: targets.isEmpty ? [media] : targets)
                },
                item(media.isFavorite ? "Unfavorite" : "Favorite", .favorite, selected: media.isFavorite) { app.library.setFavorite(!media.isFavorite, for: [media]) },
                item("Stream", .streaming) { app.presentOutput(media: media, mode: .stream) },
                item("Convert", .swap) { app.presentOutput(media: media, mode: .convert) },
                async("Add to Queue", .queue) { await MXRLibraryActions.enqueue(entry, app: app, next: false) },
                LibraryMenuItem(title: "Add to Playlist", icon: .playlist, kind: .addToPlaylist(nil, entry)),
                item("Show in Finder", .folder, enabled: local) { if let url = URL(string: media.mrl), url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } },
                item("Go to Source", .arrowRight, enabled: media.folder != nil, help: "Shows the folder that contains this file.") {
                    if let folder = media.folder {
                        app.library.navigate(to: .folder(folder.id))
                        if app.interface.library == .hidden { app.interface.library = .compact }
                    }
                },
                item("Add Subtitle Tracks", .subtitles) { app.presentAddSubtitles(media: [media]) },
                item("Add Audio Tracks", .audio) { app.presentAddAudioTracks(media: [media]) },
                item("Properties & Metadata", .info) { app.interface.present(.mediaInfo(media)) },
            ]
            if case .playlist = app.library.location, media.playlistOccurrence != nil {
                // Like Mark as Watched: the whole selection when this row is part of it.
                let targets = app.library.selection.contains(entry.id)
                    ? app.library.entries.filter { app.library.selection.contains($0.id) && $0.media?.playlistOccurrence != nil }
                    : [entry]
                figma.append(async(targets.count > 1 ? "Remove \(targets.count) Items from Playlist" : "Remove from Playlist", .remove) {
                    do { try await app.library.removeFromCurrentPlaylist(entries: targets) }
                    catch { sheets?.fail(targets.count > 1 ? "Couldn’t Remove the Items from Playlist" : "Couldn’t Remove from Playlist", error) }
                })
            }
            return Sections(figma: figma, extras: [
                async("Play Next", .next) { await MXRLibraryActions.enqueue(entry, app: app, next: true) },
            ] + [pin(entry)].compactMap { $0 })
        case .playlist(let playlist):
            let entry = LibraryEntry.playlist(playlist)
            return Sections(figma: [
                async("Play", .playback) { await MXRLibraryActions.playContainer(entry, app: app) },
                item(playlist.isFavorite ? "Unfavorite" : "Favorite", .favorite, selected: playlist.isFavorite) { app.library.setPlaylistFavorite(!playlist.isFavorite, playlist: playlist) },
                async("Shuffle", .shuffleRight) { await MXRLibraryActions.shuffleContainer(entry, app: app) },
                async("Export Playlist", .save) { await LibraryExport.export(playlist, app: app, sheets: sheets) },
                async("Add to Queue", .queue) { await MXRLibraryActions.enqueue(entry, app: app, next: false) },
                async("Add Subtitle Tracks", .subtitles) { await MXRLibraryActions.addSubtitles(for: entry, scope: .playlist, app: app) },
                async("Add Audio Tracks", .audio) { MXRLibraryActions.addAudioTracks(to: await MXRLibraryActions.media(for: entry, app: app), place: "playlist", app: app) },
                info(playlist.name, [playlist.itemCount == 1 ? "1 item" : "\(playlist.itemCount) items"] + (playlist.duration.map { [$0.formatted(.summary)] } ?? [])),
            ], extras: [
                item("Rename…", .edit) { sheets?.present(.renamePlaylist(playlist)) },
                item("Delete…", .remove) { sheets?.present(.deletePlaylist(playlist)) },
            ] + [pin(entry)].compactMap { $0 })
        case .folderEntry(let folder):
            let entry = LibraryEntry.folder(folder)
            var lines = [folder.itemCount.map { $0 == 1 ? "1 item" : "\($0) items" } ?? ""].filter { !$0.isEmpty }
            if let url = folder.url { lines.append(url.isFileURL ? url.path : url.absoluteString) }
            var extras = [pin(entry)].compactMap { $0 }
            if folder.isEntryPoint { extras.append(item("Remove from Library…", .remove) { sheets?.present(.removeFolder(folder)) }) }
            return Sections(figma: [
                async("Play", .playback) { await MXRLibraryActions.playContainer(entry, app: app) },
                async("Shuffle", .shuffleRight) { await MXRLibraryActions.shuffleContainer(entry, app: app) },
                async("Add to Queue", .queue) { await MXRLibraryActions.enqueue(entry, app: app, next: false) },
                LibraryMenuItem(title: "Add to Playlist", icon: .playlist, kind: .addToPlaylist(nil, entry)),
                async("Add Subtitle Tracks", .subtitles) { await MXRLibraryActions.addSubtitles(for: entry, scope: .folder, app: app) },
                item("Show in Finder", .folder, enabled: folder.url?.isFileURL == true) { if let url = folder.url { NSWorkspace.shared.activateFileViewerSelecting([url]) } },
                item("Resync", .refresh) { app.library.rescan(folder.id) },
                info(folder.name, lines),
            ], extras: extras)
        case .stream(let stream):
            let entry = LibraryEntry.stream(stream)
            return Sections(figma: [
                async("Play", .playback) { await MXRLibraryActions.playContainer(entry, app: app) },
                async("Add to Queue", .queue) { await MXRLibraryActions.enqueue(entry, app: app, next: false) },
                LibraryMenuItem(title: "Add to Playlist", icon: .playlist, kind: .addToPlaylist(nil, entry)),
                item("Rename…", .edit) { sheets?.present(.renameStream(stream)) },
                item("Remove…", .remove) { sheets?.present(.removeStream(stream)) },
                info(stream.name, [stream.itemCount.map { $0 == 1 ? "1 item" : "\($0) items" } ?? ""] + stream.urls.prefix(3).map(\.absoluteString)),
            ], extras: [pin(entry)].compactMap { $0 })
        case .collection(let entry):
            if case .link = entry { return Sections(figma: [], extras: [pin(entry)].compactMap { $0 }) }
            return Sections(figma: [
                async("Play", .playback) { await MXRLibraryActions.playContainer(entry, app: app) },
                async("Shuffle", .shuffleRight) { await MXRLibraryActions.shuffleContainer(entry, app: app) },
                async("Add to Queue", .queue) { await MXRLibraryActions.enqueue(entry, app: app, next: false) },
                LibraryMenuItem(title: "Add to Playlist", icon: .playlist, kind: .addToPlaylist(nil, entry)),
            ], extras: [pin(entry)].compactMap { $0 })
        }
    }

    static func kind(for entry: LibraryEntry) -> MXRLibraryPopupKind {
        switch entry {
        case .media(let media): .file(media)
        case .playlist(let playlist): .playlist(playlist)
        case .folder(let folder): .folderEntry(folder)
        case .stream(let stream): .stream(stream)
        default: .collection(entry)
        }
    }
}

// MARK: - Design-system popups (D025, L07)

extension LibraryMenus {
    /// The menu rows for `kind` as design-system popup items (Figma library menus 2404:13340, 2139:8935,
    /// 2459:9389, sort 856:2215, view 858:3290). `withExtras` adds the Mac conveniences after a
    /// separator (right-click menu).
    static func popupItems(for kind: MXRLibraryPopupKind, app: AppModel, sheets: LibrarySheetCenter?, rowIndex: Int?,
                           allSorts: Bool = false, withExtras: Bool = false) -> [MXRMenuItem] {
        switch kind {
        case .sort:
            return (allSorts ? LibrarySort.allCases : app.library.availableSorts).map { sort in
                MXRMenuItem(sort.title, isChecked: sort == app.library.sort) { app.library.setSort(sort) }
            }
        case .view(let compact):
            return LibraryViewMode.allCases.map { mode in
                MXRMenuItem(mode.title, icon: mode == .grid ? .grid : .list, iconTone: .mono,
                            isChecked: mode == (compact ? app.library.compactViewMode : app.library.fullViewMode)) {
                    if compact { app.library.compactViewMode = mode } else { app.library.fullViewMode = mode }
                }
            }
        default:
            let sections = sections(for: kind, app: app, sheets: sheets, rowIndex: rowIndex) {}
            func convert(_ item: LibraryMenuItem) -> MXRMenuItem {
                switch item.kind {
                case .perform(let action):
                    return MXRMenuItem(item.title, icon: item.icon, iconState: item.iconState, isChecked: item.selected, isEnabled: item.enabled, action: action)
                case .addToPlaylist(_, let target):
                    // Playlists load when the submenu opens, not while the rows are built.
                    return .submenu(item.title, icon: item.icon, onOpen: { app.library.loadPlaylistsIfNeeded() }) {
                        playlistItems(for: target, app: app, sheets: sheets)
                    }
                }
            }
            var result = sections.figma.map(convert)
            if withExtras, !sections.extras.isEmpty { result += [.separator] + sections.extras.map(convert) }
            return result
        }
    }

    /// "New Playlist…" and one row per playlist (the shared ``MXRPlayerMenus/playlistItems``),
    /// acting on the selection that contains `target`.
    @MainActor static func playlistItems(for target: LibraryEntry?, app: AppModel, sheets: LibrarySheetCenter?) -> [MXRMenuItem] {
        MXRPlayerMenus.playlistItems(app, newPlaylist: {
            if let target { Task { await MXRLibraryActions.newPlaylist(for: target, app: app) } }
        }, media: {
            guard let target else { return [] }
            return await MXRLibraryActions.media(forSelectionContaining: target, app: app)
        }, onError: { title, error in sheets?.fail(title, error) })
    }
}

extension View {
    /// Presents the library menu for `kind` in the design-system popup beside this view (no arrow).
    func mxrLibraryPopup(isPresented: Binding<Bool>, kind: MXRLibraryPopupKind, allSorts: Bool = false, rowIndex: Int? = nil,
                         placement: MXRPopupPlacement = .below(.trailing),
                         leading: @escaping @MainActor () -> [MXRMenuItem] = { [] }) -> some View {
        modifier(LibraryPopupModifier(isPresented: isPresented, kind: kind, allSorts: allSorts, rowIndex: rowIndex,
                                      placement: placement, leading: leading))
    }

    /// The row's right-click menu: the same items as the ⋯ card, plus the Mac extras.
    func mxrLibraryContextMenu(entry: LibraryEntry, rowIndex: Int?) -> some View {
        modifier(LibraryContextMenuModifier(entry: entry, rowIndex: rowIndex))
    }
}

private struct LibraryPopupModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(LibrarySheetCenter.self) private var sheets: LibrarySheetCenter?
    @Binding var isPresented: Bool
    let kind: MXRLibraryPopupKind
    let allSorts: Bool
    let rowIndex: Int?
    let placement: MXRPopupPlacement
    let leading: @MainActor () -> [MXRMenuItem]

    func body(content: Content) -> some View {
        let style: MXRPopupStyle = if case .sort = kind { .textMenu } else { .contextMenu }
        content.mxrPopupMenu(isPresented: $isPresented, placement: placement, style: style) {
            let head = leading()
            let rows = LibraryMenus.popupItems(for: kind, app: app, sheets: sheets, rowIndex: rowIndex, allSorts: allSorts)
            return head.isEmpty ? rows : head + [.separator] + rows
        }
    }
}

private struct LibraryContextMenuModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(LibrarySheetCenter.self) private var sheets: LibrarySheetCenter?
    let entry: LibraryEntry
    let rowIndex: Int?

    func body(content: Content) -> some View {
        content.mxrContextMenu(style: .contextMenu) {
            LibraryMenus.popupItems(for: LibraryMenus.kind(for: entry), app: app, sheets: sheets, rowIndex: rowIndex, withExtras: true)
        }
    }
}

/// The Figma library menu card drawn in place (gallery specimens and tests); the product presents
/// the same rows through ``SwiftUI/View/mxrLibraryPopup(isPresented:kind:allSorts:rowIndex:placement:leading:)``.
public struct MXRLibraryPopupView: View {
    @Environment(AppModel.self) private var app
    @Environment(LibrarySheetCenter.self) private var sheets: LibrarySheetCenter?
    let kind: MXRLibraryPopupKind
    var allSorts: Bool
    private let rowIndex: Int?

    public init(kind: MXRLibraryPopupKind, allSorts: Bool = false, rowIndex: Int? = nil) {
        self.kind = kind
        self.allSorts = allSorts
        self.rowIndex = rowIndex
    }

    public var body: some View {
        let style: MXRPopupStyle = if case .sort = kind { .textMenu } else { .contextMenu }
        MXRMenuCard(items: LibraryMenus.popupItems(for: kind, app: app, sheets: sheets, rowIndex: rowIndex, allSorts: allSorts),
                    style: style, activates: true)
    }
}

@MainActor
enum LibraryExport {
    /// "Export Playlist": an extended M3U next to wherever the user chooses.
    static func export(_ playlist: Playlist, app: AppModel, sheets: LibrarySheetCenter?) async {
        let items = await app.library.allMedia(at: .playlist(playlist.id))
        let panel = NSSavePanel()
        panel.nameFieldStringValue = playlist.name + ".m3u"
        if let type = UTType(filenameExtension: "m3u") { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "#EXTM3U\n" + items.map { media in
            "#EXTINF:\(Int(media.duration?.seconds ?? -1)),\(media.listTitle.replacingOccurrences(of: "\n", with: " "))\n\(media.mrl)"
        }.joined(separator: "\n") + "\n"
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { sheets?.fail("Couldn’t Export “\(playlist.name)”", error) }
    }
}
