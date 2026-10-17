import AppKit
import MXRCore
import MXRDesign
import SwiftUI

/// A library row (32 pt thumb + name, Figma media 2404:9167 / playlist 2459:9352) or a grid card.
///
/// Mac list manners: a click selects a media row (⌘ toggles, ⇧ extends), a double-click plays it;
/// containers (folders, playlists, albums, links) open on a click, as in the video's address-line
/// navigation. Hover brightens the label to FG/2 (2404:9168 / 2404:9256) and shows ⋯ at the row end.
struct LibraryEntryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.mxrLibraryPreviewHover) private var previewHover
    let entry: LibraryEntry
    var cardSize: CGSize?
    var showSubtitle = false
    var homeCard = false
    var progressForAll = true
    var rowIndex: Int?
    /// The resting label color when the place sets one instead of the watched state: Home lists
    /// FG/A3 rows in the compact panel (1106:5633) and FG/A1 captions in the full window (6261:15093).
    var restingColor: ThemeColor?
    /// Called on a click so the list can take keyboard focus (↑↓, Return).
    var activate: (() -> Void)?
    @State private var hovered = false
    @State private var popup = false

    private var current: Bool { entry.media.map { MXRLibraryActions.isCurrentMedia($0, app: app) } ?? false }
    private var selected: Bool { app.library.selection.contains(entry.id) }
    private var isHovered: Bool { hovered || previewHover == entry.id }
    private var color: ThemeColor {
        if current { return Theme.Color.accentMain }
        if isHovered || selected || popup { return Theme.Color.fg2 }
        if let restingColor { return restingColor }
        return Self.restingColor(of: entry, card: cardSize != nil)
    }

    /// The label color at rest. Figma's compact panel (sidebar 848:1996) draws every navigation row
    /// in FG/A3 (217:229): the Videos root's Shows / Films / Anime, The Wand, S01 / S02, Music's
    /// Songs / Albums / Artists / Genres, My Songs, Network's Podcasts / Radio. Only playable rows
    /// (media 2404:9181, an unwatched one) and playlist rows (2459:9359) rest at FG/A1 (247:711);
    /// a watched media row dims to FG/A3 (2404:9152). Grid cards caption in FG/A1 like the full
    /// window's folder tiles (6261:15093).
    static func restingColor(of entry: LibraryEntry, card: Bool) -> ThemeColor {
        if let media = entry.media { return media.isWatched ? Theme.Color.fgA3 : Theme.Color.fgA1 }
        switch entry {
        case .playlist: return Theme.Color.fgA1
        default: return card || entry.destination == nil ? Theme.Color.fgA1 : Theme.Color.fgA3
        }
    }

    var body: some View {
        Group {
            if let size = cardSize { card(size) } else { row }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if entry.destination == nil { MXRLibraryActions.open(entry, app: app) } }
        .simultaneousGesture(TapGesture().onEnded { click() })
        .mxrLibraryContextMenu(entry: entry, rowIndex: rowIndex)
        .onHover { hovered = $0 }
        .onAppear {
            if let rowIndex { app.library.loadMoreIfNeeded(at: rowIndex) }
            else { app.library.loadMoreIfNeeded(after: entry) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(entry.title)
        .accessibilityValue(entry.media?.isWatched == true ? "Watched" : current ? "Now playing" : "")
        .accessibilityAction { MXRLibraryActions.open(entry, app: app) }
        .accessibilityAction(named: "Show actions") { popup = true }
        .modifier(LibraryDrag(entry: entry, library: app.library))
    }

    private func click() {
        activate?()
        let flags = NSEvent.modifierFlags
        let toggling = flags.contains(.command), extending = flags.contains(.shift)
        if entry.destination != nil, !toggling, !extending {
            MXRLibraryActions.open(entry, app: app)
        } else {
            app.library.select(entry, extending: extending, toggling: toggling)
        }
    }

    /// Audio cards caption the song title above its artist ("untangle" / "juxtopposed"); other
    /// cards use the row text.
    private var caption: String {
        if homeCard || (entry.media?.kind == .audio && entry.media?.artist?.isEmpty == false) { return entry.media?.title ?? entry.title }
        return entry.title
    }

    private func card(_ size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: LibraryGeometry.gridTitleGap) {
            LibraryArtwork(entry: entry, size: size, radius: LibraryGeometry.gridRadius, isCurrent: current, large: true, showProgress: progressForAll)
            VStack(alignment: .leading, spacing: Theme.Spacing.gap10) {
                Text(caption)
                    .mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(color).lineLimit(1)
                    .frame(height: LibraryGeometry.cardCaptionHeight)
                if showSubtitle, let subtitle = entry.mxrSubtitle, !subtitle.isEmpty {
                    Text(subtitle).mxrTextStyle(Theme.Font.bodyLarge).foregroundStyle(Theme.Color.fgA3).lineLimit(1)
                        .frame(height: LibraryGeometry.cardCaptionHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: size.width, alignment: .leading)
        .overlay(alignment: .topTrailing) { more.padding(Theme.Spacing.gap8).frame(height: size.height, alignment: .top) }
    }

    private var row: some View {
        HStack(spacing: Theme.Metric.Library.mediaRow.gap) {
            if entry.media != nil || entry.mxrArtworkMedia != nil {
                LibraryArtwork(entry: entry, size: Theme.Metric.Library.thumb.size, isCurrent: current, showProgress: progressForAll)
            } else {
                MXRIcon(entry.mxrIcon).frame(width: Theme.Metric.Library.thumb.width, height: Theme.Metric.Library.thumb.height)
            }
            // A file name keeps its end (episode number, extension) when it truncates, as in Finder.
            Text(entry.title).mxrTextStyle(Theme.Font.body).foregroundStyle(color)
                .lineLimit(1).truncationMode(entry.media == nil ? .tail : .middle).frame(maxWidth: .infinity, alignment: .leading)
            more
        }
        .frame(height: Theme.Metric.Library.mediaRow.height)
        .background {
            // Selection: the design's row-hover fill (BG/A2, menu row 2107:5934) behind the whole row.
            if selected {
                RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgA2)
                    .padding(.horizontal, -Theme.Spacing.gap4)
            }
        }
    }

    /// The ⋯ button stays in the hierarchy (invisible) so the open card keeps its anchor while the
    /// pointer travels into it; it only becomes visible on hover or while the card is open.
    private var more: some View {
        let visible = isHovered || popup
        return LibraryIconButton(icon: .more, label: "Actions for \(entry.title)") { popup = true }
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .mxrLibraryPopup(isPresented: $popup, kind: LibraryMenus.kind(for: entry), rowIndex: rowIndex)
            .accessibilityHidden(true)
    }
}

/// Dragging a row into the queue: the row's media, or the whole selection when the row is part of it.
private struct LibraryDrag: ViewModifier {
    let entry: LibraryEntry
    let library: LibraryModel

    func body(content: Content) -> some View {
        if entry.media != nil || entry.folderURL != nil {
            content.onDrag { provider() }
        } else {
            content
        }
    }

    @MainActor private func provider() -> NSItemProvider {
        if library.selection.count > 1, library.selection.contains(entry.id) {
            let urls = library.entries.filter { library.selection.contains($0.id) }.compactMap { $0.media?.mrl ?? $0.folderURL?.absoluteString }
            return NSItemProvider(object: urls.joined(separator: "\n") as NSString)
        }
        if let media = entry.media, let url = URL(string: media.mrl) { return NSItemProvider(object: url as NSURL) }
        if let url = entry.folderURL { return NSItemProvider(object: url as NSURL) }
        return NSItemProvider()
    }
}

private extension LibraryEntry {
    var folderURL: URL? { if case .folder(let folder) = self { return folder.url }; return nil }
}
