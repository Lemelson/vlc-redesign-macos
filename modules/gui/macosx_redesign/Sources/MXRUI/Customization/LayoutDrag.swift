import CoreTransferable
import MXRCore
import MXRDesign
import SwiftUI
import UniformTypeIdentifiers

/// A tile or an existing bar item. The payload contains identity only: the LayoutStore owns
/// the editable layout, so moving a control never makes a second copy of player state.
public struct MXRLayoutDragPayload: Codable, Hashable, Sendable, Transferable {
    private var itemID: String?
    private var control: PlayerControl?

    public static func tile(_ control: PlayerControl) -> Self { Self(itemID: nil, control: control) }
    public static func placed(_ item: LayoutItem) -> Self { Self(itemID: item.id, control: nil) }

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mxrPlayerLayoutItem)
    }

    /// Inserts a palette tile, or moves an existing item, into the active draft.
    @MainActor @discardableResult
    public func place(in zone: LayoutZone, at index: Int, app: AppModel) -> Bool {
        guard app.interface.isCustomizing, let draft = app.layouts.draft else { return false }
        if case .bottom(let row) = zone, !(-1...draft.bottom.count).contains(row) { return false }
        if let itemID {
            guard draft.location(of: itemID) != nil else { return false }
            app.layouts.updateDraft { $0.move(itemID, to: zone, at: index) }
        } else if let control {
            guard MXRCustomizationPalette.controls(for: draft, kind: app.layoutKind).contains(control) else { return false }
            app.layouts.updateDraft { $0.insert(LayoutItem(control), in: zone, at: index) }
        } else {
            return false
        }
        return true
    }

    /// "Move to New Row" starts the row where the Customize band is drawn: nearest the video
    /// (``LayoutZone/newFirstRow``), as a drop on the band does and as 19m26.3 → 19m27.6 builds the
    /// seek row above the transport (D051). It never leaves the band empty and adds a row below.
    @MainActor @discardableResult
    public func moveToNewRow(app: AppModel) -> Bool {
        place(in: .newFirstRow, at: 0, app: app)
    }

    /// Dropping a placed control into the central palette removes it from the player.
    @MainActor @discardableResult
    public func remove(from app: AppModel) -> Bool {
        guard app.interface.isCustomizing, let itemID,
              app.layouts.draft?.location(of: itemID) != nil else { return false }
        app.layouts.updateDraft { $0.remove(itemID) }
        return true
    }
}

extension UTType {
    fileprivate static let mxrPlayerLayoutItem = UTType(exportedAs: "org.videolan.vlc-redesign.player-layout-item")
}

enum MXRCustomizationPalette {
    static func controls(for layout: PlayerLayout, kind: LayoutStore.Kind) -> [PlayerControl] {
        let defaults: PlayerLayout = kind == .music ? .music : .video
        let removedDefaults = defaults.allItems.map(\.control).filter {
            !PlayerControl.tiles.contains($0) && !layout.contains($0)
        }
        // Removed default controls return to the palette too, so a saved layout can restore them.
        return layout.availableTiles + removedDefaults
    }

    /// The dashed icon box of a tile. Figma 6587:18867 uses three: the 24 × 32 slot (spacer, divider),
    /// the 30 × 32 `Icon Wrapper` and the bare 28 × 28 `Icon` (Forward/Backward 15s and most
    /// information tiles), so labels under a 28 pt box sit 4 pt higher.
    static func iconSize(for control: PlayerControl) -> CGSize {
        switch control {
        case .spacer, .divider: Theme.Metric.Customization.narrowIcon.size
        case .forward15, .backward15, .quit, .settings, .goHome, .thumbnail, .fileName, .artistName,
             .folderNameTile, .playlistName, .properties, .replay, .chapters, .favorite, .bookmarks:
            Theme.Metric.Customization.smallIcon.size
        default: Theme.Metric.Customization.tallIcon.size
        }
    }

    /// A tile hugs its content like the Figma frames (6587:18876 is 65 pt, 6587:18884 82 pt,
    /// 6587:18893 78 pt): the icon box, the 16 pt gap and one line of text per label line.
    static func tileHeight(for control: PlayerControl) -> CGFloat {
        let lines = CGFloat(control.tileLabel.split(separator: "\n", omittingEmptySubsequences: false).count)
        return iconSize(for: control).height + Theme.Spacing.gap16 + Theme.Font.body.lineHeight * lines
    }

    /// A row is as tall as its tallest tile (the grid is a wrapping auto layout with `rowGap` between
    /// rows, so the Figma rows start at 128, 248, 368 and 484).
    static func rowHeight(_ row: [PlayerControl]) -> CGFloat {
        row.map(tileHeight(for:)).max() ?? 0
    }

    /// Height of the whole grid with its padding.
    static func contentHeight(rows: [[PlayerControl]]) -> CGFloat {
        let box = Theme.Metric.Customization.body.padding
        return box.top + box.bottom + rows.map(rowHeight).reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * Theme.Metric.Customization.gridRowGap
    }

    static func overflows(rows: [[PlayerControl]], available: CGFloat) -> Bool {
        contentHeight(rows: rows) > available
    }

    /// The bottom fade of an overflowing palette `available` points tall (SD-M2): a short fade
    /// (one label's height) over the bottom edge only, so a row that is cut there softens into
    /// "more below" instead of ending at a hard edge, while everything above it stays at full
    /// opacity and never reads as disabled.
    static func fadeHeight(available: CGFloat) -> CGFloat {
        min(available, Theme.Font.body.lineHeight * 2)
    }
}

extension View {
    /// Player bars apply this to each LayoutItem. In edit mode the control is outlined and
    /// draggable; normal playback retains the original view and its actions.
    ///
    /// `outline` lets neighbours that Figma outlines as one group (time + seek bar + duration,
    /// 2115:7285) share a single dashed rectangle (CMP-13); each member stays individually draggable.
    public func mxrLayoutDraggable(_ item: LayoutItem, outline: MXRLayoutOutline = .single) -> some View {
        modifier(MXRLayoutDraggableModifier(item: item, outline: outline))
    }

    /// Accepts an item before the specified index; `bottom(rowCount)` creates a new row.
    public func mxrLayoutDropTarget(zone: LayoutZone, index: Int) -> some View {
        modifier(MXRLayoutDropTargetModifier(zone: zone, index: index))
    }
}

/// How an item's edit-mode outline joins its row neighbours.
public struct MXRLayoutOutline: Equatable, Sendable {
    public var joinsLeading: Bool
    public var joinsTrailing: Bool
    public init(joinsLeading: Bool = false, joinsTrailing: Bool = false) {
        self.joinsLeading = joinsLeading; self.joinsTrailing = joinsTrailing
    }
    public static let single = MXRLayoutOutline()
}

/// A dashed rectangle whose joined sides stay open and whose top and bottom run on into the
/// neighbouring item across `gap`, so a group reads as one outline.
private struct MXRGroupOutline: Shape {
    let outline: MXRLayoutOutline
    let gap: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let left = rect.minX - (outline.joinsLeading ? gap / 2 : 0)
        let right = rect.maxX + (outline.joinsTrailing ? gap / 2 : 0)
        path.move(to: CGPoint(x: left, y: rect.minY)); path.addLine(to: CGPoint(x: right, y: rect.minY))
        path.move(to: CGPoint(x: left, y: rect.maxY)); path.addLine(to: CGPoint(x: right, y: rect.maxY))
        if !outline.joinsLeading { path.move(to: CGPoint(x: rect.minX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)) }
        if !outline.joinsTrailing { path.move(to: CGPoint(x: rect.maxX, y: rect.minY)); path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)) }
        return path
    }
}

private struct MXRLayoutDraggableModifier: ViewModifier {
    @Environment(InterfaceModel.self) private var interface
    @Environment(AppModel.self) private var app
    let item: LayoutItem
    let outline: MXRLayoutOutline

    func body(content: Content) -> some View {
        // Player - customize (2107:5604): the cone is not a tile (no box, not movable).
        if interface.isCustomizing && item.control != .logo {
            content
                // Edit mode shows every control in its enabled default state (Figma draws none
                // disabled or dimmed) and the controls do not act: a click picks up the tile.
                .environment(\.mxrLayoutEditing, true)
                .allowsHitTesting(false)
                .overlay {
                    // Spacers keep their drop slot and stay movable, but Figma draws no box for them.
                    if item.control != .spacer {
                        outlineShape
                            .stroke(Theme.Color.fgA3, style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                                       dash: Theme.Stroke.customizeOutlineDash))
                            .padding(.horizontal, -outset.width)
                            .padding(.vertical, -outset.height)
                    }
                }
                .overlay { Rectangle().fill(.clear).contentShape(.rect) }
                .draggable(MXRLayoutDragPayload.placed(item))
                .accessibilityLabel("Move \(item.control.title)")
                .mxrContextMenu(style: .contextMenu) { [app, item] in
                    MXRLayoutEditCommand.all(for: item, app: app).flatMap { command in
                        (command.separatedAbove ? [MXRMenuItem.separator] : [])
                            + [MXRMenuItem(command.menuTitle) { command.perform() }]
                    }
                }
                .accessibilityActions {
                    ForEach(MXRLayoutEditCommand.all(for: item, app: app), id: \.menuTitle) { command in
                        Button(command.accessibilityName) { command.perform() }
                    }
                }
        } else {
            content
        }
    }

    private var outlineShape: AnyShape {
        outline == .single ? AnyShape(Rectangle())
            : AnyShape(MXRGroupOutline(outline: outline, gap: Theme.Metric.ControlBar.transportGroup.gap))
    }

    /// How far the Figma tile box extends beyond the control's own frame (metrics.json
    /// `customization.outline`): play 34 pt tall around the 28 pt button, the time + seek group
    /// 36 pt tall, the title box padded around its text, and the volume box 130×36 around
    /// the 120×28 speaker and cone (2115:7291).
    private var outset: CGSize {
        switch item.control {
        case .playPause: CGSize(width: 0, height: Theme.Metric.Customization.outlinePlayVertical)
        case .currentTime, .seekBar, .duration: CGSize(width: 0, height: Theme.Metric.Customization.outlineSeekGroupVertical)
        case .title, .fileName, .artistName, .playlistName:
            CGSize(width: Theme.Metric.Customization.outlineTitleHorizontal, height: 0)
        case .volume:
            CGSize(width: Theme.Metric.Customization.outlineVolumeHorizontal, height: Theme.Metric.Customization.outlineVolumeVertical)
        default: .zero
        }
    }

}

/// A placed tile's edit commands in Customize. Its context menu and its VoiceOver actions are both
/// built from this list, so they always do the same thing.
struct MXRLayoutEditCommand {
    let menuTitle: String
    let accessibilityName: String
    var separatedAbove = false
    let perform: @MainActor () -> Void

    @MainActor static func all(for item: LayoutItem, app: AppModel) -> [Self] {
        let payload = MXRLayoutDragPayload.placed(item)
        func append(to zone: LayoutZone) {
            _ = payload.place(in: zone, at: app.playerLayout.items(in: zone).count, app: app)
        }
        return [
            Self(menuTitle: "Move to Top Bar", accessibilityName: "Move to top bar") { append(to: .top) },
            Self(menuTitle: "Move to Control Bar", accessibilityName: "Move to control bar") { append(to: .bottom(0)) },
            Self(menuTitle: "Move to New Row", accessibilityName: "Move to new row") { _ = payload.moveToNewRow(app: app) },
            Self(menuTitle: "Remove from Player", accessibilityName: "Remove from player", separatedAbove: true) {
                _ = payload.remove(from: app)
            },
        ]
    }
}

extension EnvironmentValues {
    /// True inside a player control shown as a Customize tile: draw it in its enabled default state.
    @Entry public var mxrLayoutEditing = false
}

private struct MXRLayoutDropTargetModifier: ViewModifier {
    @Environment(AppModel.self) private var app
    @State private var isTargeted = false
    let zone: LayoutZone
    let index: Int

    func body(content: Content) -> some View {
        if app.interface.isCustomizing {
            content
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    if isTargeted {
                        Rectangle().fill(Theme.Color.accentMain).frame(width: Theme.Stroke.iconActive)
                    }
                }
                .dropDestination(for: MXRLayoutDragPayload.self) { items, _ in
                    guard let item = items.first else { return false }
                    return item.place(in: zone, at: index, app: app)
                } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}
