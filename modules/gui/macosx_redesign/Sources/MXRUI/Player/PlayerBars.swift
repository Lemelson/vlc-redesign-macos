import MXRCore
import MXRDesign
import SwiftUI

public struct MXRTopBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mxrBarsBesidePicture) private var besidePicture // D053: Light bars over the canvas base
    private let onPictureInPicture: (() -> Void)?
    public init(onPictureInPicture: (() -> Void)? = nil) {
        self.onPictureInPicture = onPictureInPicture
    }
    public var body: some View {
        let box = Theme.Metric.Window.topBar
        let items = PlayerGeometry.topItems(app.playerLayout.top,
                                           fullLibrary: app.interface.library == .full && !app.interface.isCustomizing)
        // D022: the host's traffic lights share this row; the cone follows them with the group gap.
        let reserve = max(0, CGFloat(app.interface.windowControlsReserve) - box.padding.leading)
        PlayerRowLayout(top: true) {
            if reserve > 0 { Color.clear.frame(width: reserve).layoutValue(key: PlayerControlKey.self, value: .logo) }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PlayerControlView(control: item.control, inTopBar: true, onPictureInPicture: onPictureInPicture)
                    .layoutValue(key: PlayerControlKey.self, value: item.control)
                    .mxrLayoutDraggable(item)
                    .mxrLayoutDropTarget(zone: .top, index: index)
            }
        }
        // SD-02: the trailing drop slot overlays the row so edit mode keeps the real layout.
        .overlay(alignment: .trailing) {
            if app.interface.isCustomizing {
                Color.clear.frame(width: Theme.Spacing.gap8)
                    .mxrLayoutDropTarget(zone: .top, index: app.playerLayout.top.count)
                    .offset(x: Theme.Spacing.gap8)
            }
        }
        .padding(box.padding)
        .frame(height: box.height)
        .background {
            ZStack {
                if colorScheme == .light || app.interface.library == .full || app.interface.isCustomizing {
                    MXRBackdropSurface(tint: Theme.Color.bgA3Transparent, material: .headerView,
                                       overCanvasBase: besidePicture)
                } else { Rectangle().fill(Theme.Color.bgA3) }
                // WT-10: empty bar space moves the window; double-click zooms or minimizes.
                MXRWindowDragArea(onMouseDown: { app.interface.dismissTransientPopup() })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Player title bar")
        .mxrPopupOwner(.playerTopBar)
    }
}

public struct MXRControlBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mxrBarsBesidePicture) private var besidePicture // D053: Light bars over the canvas base
    private let usesOpaqueVideoBackground: Bool
    private let onPictureInPicture: (() -> Void)?
    /// The dark video scene has an opaque footer; customization, components, music and Light remain translucent.
    public init(usesOpaqueVideoBackground: Bool = false, onPictureInPicture: (() -> Void)? = nil) {
        self.usesOpaqueVideoBackground = usesOpaqueVideoBackground
        self.onPictureInPicture = onPictureInPicture
    }
    public var body: some View {
        let box = Theme.Metric.ControlBar.bar
        let rows = app.playerLayout.bottom.count
        VStack(spacing: 0) {
            // 2107:5604: in Customize a one-row layout gets an empty bar row above it; dropping an
            // item there starts a new row nearest the video (19m26.3 → 19m27.6).
            ForEach(0..<(PlayerGeometry.controlRows(layoutRows: rows, customizing: app.interface.isCustomizing) - rows),
                    id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: box.height)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.controlBarTopBorder)
                    }
                    .mxrLayoutDropTarget(zone: .newFirstRow, index: 0)
                    .accessibilityElement()
                    .accessibilityLabel("New control bar row")
            }
            ForEach(Array(app.playerLayout.bottom.enumerated()), id: \.offset) { rowIndex, items in
                // SD-02: edit mode lays out at the real width, so the editor is WYSIWYG.
                Group {
                    if app.interface.isCustomizing {
                        row(items: items, index: rowIndex)
                    } else {
                        ViewThatFits(in: .horizontal) {
                            row(items: items, index: rowIndex)
                            row(items: PlayerGeometry.compactItems(items), index: rowIndex,
                                overflow: items.filter { !PlayerGeometry.compactItems(items).contains($0) })
                        }
                    }
                }
                .frame(height: Theme.Metric.ControlBar.iconButton.height)
                .padding(.top, box.padding.top)
                .padding(.bottom, box.padding.bottom)
                .padding(.leading, box.padding.leading)
                .padding(.trailing, box.padding.trailing)
                .overlay(alignment: .top) {
                    if colorScheme == .light || app.interface.isCustomizing {
                        Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.controlBarTopBorder)
                    }
                }
            }
        }
        .background {
            if usesOpaqueVideoBackground && colorScheme == .dark && !app.player.isAudioOnly && !app.interface.isCustomizing {
                Rectangle().fill(Theme.Color.bgA3)
            } else {
                MXRBackdropSurface(tint: Theme.Color.bgA3Transparent, material: .headerView,
                                   overCanvasBase: besidePicture)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playback controls")
        .mxrPopupOwner(.playerControlBar)
        .overlay(alignment: .bottom) {
            if app.interface.isCustomizing {
                Color.clear.frame(height: Theme.Spacing.gap8)
                    .mxrLayoutDropTarget(zone: .bottom(app.playerLayout.bottom.count), index: 0)
            }
        }
    }
    /// 2115:7285: time, seek bar and duration are outlined as one group in edit mode (CMP-13).
    private func outline(at index: Int, in items: [LayoutItem]) -> MXRLayoutOutline {
        let group: Set<PlayerControl> = [.currentTime, .seekBar, .duration]
        guard group.contains(items[index].control) else { return .single }
        return MXRLayoutOutline(joinsLeading: index > 0 && group.contains(items[index - 1].control),
                                joinsTrailing: index + 1 < items.count && group.contains(items[index + 1].control))
    }
    private func row(items: [LayoutItem], index row: Int, overflow: [LayoutItem] = []) -> some View {
        PlayerRowLayout(top: false) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                PlayerControlView(control: item.control, onPictureInPicture: onPictureInPicture)
                    .layoutValue(key: PlayerControlKey.self, value: item.control)
                    .mxrLayoutDraggable(item, outline: outline(at: index, in: items))
                    .mxrLayoutDropTarget(zone: .bottom(row), index: index)
            }
            if !overflow.isEmpty {
                MXRPlayerOverflowButton(controls: overflow.map(\.control), onPictureInPicture: onPictureInPicture)
                .layoutValue(key: PlayerControlKey.self, value: .menu)
            }
        }
        // SD-02: the trailing drop slot overlays the row instead of becoming a flexible layout child.
        .overlay(alignment: .trailing) {
            if app.interface.isCustomizing {
                Color.clear.frame(width: Theme.Spacing.gap8)
                    .mxrLayoutDropTarget(zone: .bottom(row), index: items.count)
                    .offset(x: Theme.Spacing.gap8)
            }
        }
    }

}

private struct PlayerControlKey: LayoutValueKey { static let defaultValue = PlayerControl.spacer }

enum MXRControlTitles {
    /// A-01: media outside a library folder still get the chip (12-continue-watching 14m09.8 shows
    /// "Videos" on DON'T BLINK); it names and opens the category instead of a parent directory.
    static func folderChip(folder: FolderReference?, audioOnly: Bool) -> String {
        folder?.name ?? (audioOnly ? "Songs" : "Videos")
    }
}

/// Preserve the Figma grouping while allowing every item to move, disappear or move to another row.
private struct PlayerRowLayout: Layout {
    let top: Bool
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let controls = subviews.map { $0[PlayerControlKey.self] }
        let minimum = subviews.indices.reduce(CGFloat.zero) { width, index in
            let control = controls[index]
            let itemWidth: CGFloat
            if control == .seekBar { itemWidth = Theme.Metric.ControlBar.playButton.width }
            else if control.isFlexible || (top && [.title, .folderName, .folderNameTile].contains(control)) { itemWidth = 0 }
            else { itemWidth = subviews[index].sizeThatFits(.unspecified).width }
            return width + itemWidth + (index == 0 ? 0 : spacing(controls[index - 1], control))
        }
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? Theme.Metric.ControlBar.iconButton.height
        return CGSize(width: max(proposal.width ?? minimum, minimum), height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let controls = subviews.map { $0[PlayerControlKey.self] }
        let gaps = controls.indices.map { index in index == 0 ? 0 : spacing(controls[index - 1], controls[index]) }
        var measured = subviews.map { $0.sizeThatFits(.unspecified) }
        var titleWidth: CGFloat?
        if top {
            let widths = PlayerGeometry.headerWidths(measured.map(\.width), gaps: gaps,
                                                     title: controls.firstIndex(of: .title),
                                                     folders: controls.indices.filter { [.folderName, .folderNameTile].contains(controls[$0]) },
                                                     flexible: controls.indices.filter { controls[$0].isFlexible },
                                                     width: bounds.width)
            for index in measured.indices { measured[index].width = widths.items[index] }
            titleWidth = widths.title
        }
        // The top title is placed centred, outside the running x: neither its width nor its gap is in the row.
        let widths = PlayerGeometry.rowWidths(measured.map(\.width), gaps: gaps,
                                              spacers: controls.indices.filter { controls[$0] == .spacer },
                                              flexible: controls.indices.filter { controls[$0].isFlexible },
                                              skipped: top ? controls.indices.filter { controls[$0] == .title } : [],
                                              width: bounds.width)
        var x = bounds.minX
        for index in subviews.indices {
            let control = controls[index]
            if top && control == .title {
                // A-07: the title is centred on the window; with no room it is left out rather than drawn as "…".
                subviews[index].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center,
                                     proposal: ProposedViewSize(width: titleWidth ?? 0, height: bounds.height))
                continue
            }
            x += gaps[index]
            let width = widths[index]
            subviews[index].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                                 proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
    private func spacing(_ left: PlayerControl, _ right: PlayerControl) -> CGFloat {
        // 247:448 "Frame 11": the header cluster keeps its Figma spacing in any row it is placed in
        // (customize-7 2160:8404 puts the same ⋯ · sidebar · divider · folder run in the control bar).
        if left == .menu && right == .sidebarToggle { return Theme.Spacing.gap10 }
        if left == .sidebarToggle && right == .divider { return 0 }
        if left == .divider && (right == .folderName || right == .folderNameTile) { return 0 }
        if top { return Theme.Metric.Window.topBarLeftGroup.gap }
        // customize-7: the folder chip (2160:8410, ends at 172) and the row title cell (2160:8419, at 184).
        if (left == .folderName || left == .folderNameTile) && right == .title { return Theme.Spacing.gap12 }
        if group(left) != group(right) { return Theme.Metric.ControlBar.bar.gap }
        return group(right) == 3 ? Theme.Metric.ControlBar.trackButtonsGroup.gap : Theme.Metric.ControlBar.transportGroup.gap
    }
    private func group(_ control: PlayerControl) -> Int {
        switch control {
        case .previous, .playPause, .next, .backward10, .forward10, .backward15, .forward15: 0
        case .currentTime, .seekBar, .duration: 1
        case .volume: 2
        case .audioTracks, .subtitleTracks, .playbackSettings: 3
        case .queue: 4
        default: 5
        }
    }
}

private struct PlayerControlView: View {
    let control: PlayerControl
    var inTopBar = false
    let onPictureInPicture: (() -> Void)?
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder var body: some View {
        switch control {
        case .spacer: Color.clear.frame(minWidth: 0, maxWidth: .infinity)
        case .divider:
            MXRIcon(.divider).frame(width: Theme.Metric.iconSize, height: MXRPlayerMetrics.headerIcon.height)
        case .logo:
            MXRIcon(.vlc)
                .frame(width: Theme.Metric.Window.logoCell.width, height: Theme.Metric.Window.logoCell.height)
        case .menu:
            // The open state lives in InterfaceModel so the menu pins the top bar and Esc closes it.
            MXRPlayerIconButton(.more, title: "Open VLC menu", box: MXRPlayerMetrics.headerIcon) { app.interface.isAppMenuOpen.toggle() }
                .mxrAppMenu(isPresented: Binding(get: { app.interface.isAppMenuOpen }, set: { app.interface.isAppMenuOpen = $0 }))
        case .folderName, .folderNameTile: folderChip
        case .title:
            // A-07: the row may give the title zero width; the flexible frame and clip then draw nothing.
            // The top bar centres the bare title; in a control-bar row it is the padded 2160:8419 cell.
            title(app.windowTitle, dragsWindow: true)
                .padding(.leading, inTopBar ? 0 : MXRPlayerMetrics.rowTitleCell.padding.leading)
                .padding(.trailing, inTopBar ? 0 : MXRPlayerMetrics.rowTitleCell.padding.trailing)
                .frame(minWidth: 0, maxWidth: .infinity).clipped()
                .mxrHelp(app.windowTitleFileName)
                .accessibilityLabel(app.windowTitleFileName ?? app.windowTitle)
        case .fileName: title(app.player.media?.fileName ?? app.player.windowTitle, dragsWindow: true)
        case .artistName: title(app.player.media?.artist ?? "", dragsWindow: true)
        case .playlistName: title(app.library.breadcrumb.last?.title ?? "Playlist", dragsWindow: true)
        case .playPause: MXRPlayPauseButton()
        // S21: in subtitle timeline mode the time slots show the window bounds marked "*" (07m04.2).
        case .currentTime:
            if MXRSubtitleTimelineView.isActive(in: app) { MXRSubtitleTimelineRangeLabel(.start) } else { MXRTimeLabel(.current) }
        case .duration:
            if MXRSubtitleTimelineView.isActive(in: app) { MXRSubtitleTimelineRangeLabel(.end) } else { MXRTimeLabel(.duration) }
        case .seekBar:
            if MXRSubtitleTimelineView.isActive(in: app) {
                MXRSubtitleTimelineView(showsRangeLabels: false)
            } else { MXRSeekBar() }
        case .volume: MXRVolumeControl()
        case .thumbnail:
            MXRMediaArtwork()
                .frame(width: Theme.Metric.ControlBar.playButton.width, height: Theme.Metric.ControlBar.playButton.height)
                .clipShape(.rect(cornerRadius: Theme.Radius.md))
        case .playbackSpeed:
            MXRPlayerBarMenu(.speed) { title("\(app.player.rate.formatted())×") }.disabled(!app.player.canChangeRate)
        case .hdr:
            MXRPlayerBarMenu(.hdr) { MXRIcon(.hdr).frame(width: Theme.Metric.ControlBar.iconButton.width) }
        case .zoom:
            MXRPlayerBarMenu(.zoom) { MXRIcon(.zoom).frame(width: Theme.Metric.ControlBar.iconButton.width) }
        case .pictureInPicture:
            MXRPlayerIconButton(.pip, title: "Picture in Picture", active: app.player.isPictureInPicture) {
                if let onPictureInPicture { onPictureInPicture() }
                else { app.player.setPictureInPicture(!app.player.isPictureInPicture) }
            }.disabled(app.player.isAudioOnly || (onPictureInPicture == nil && app.capabilities.pictureInPicture == .unsupported))
        case .properties:
            MXRPlayerIconButton(.info, title: "Properties & Metadata") {
                if let media = app.player.media { app.interface.present(.mediaInfo(media)) }
            }.disabled(app.player.media == nil)
        case .replay: MXRPlayerIconButton(.replay, title: "Replay") { app.player.seek(to: .zero); app.player.play() }.disabled(!app.player.canSeek)
        case .playlists:
            MXRPlayerIconButton(.playlist, title: "Playlists") { app.library.select(.playlists); app.interface.library = .compact }
        case .chapters:
            MXRPlayerIconButton(.chapters, title: "Chapters", active: app.interface.rightPanel == .queue(.chapters)) {
                app.interface.toggleQueuePanel(.chapters)
            }
        case .bookmarks:
            MXRPlayerIconButton(.bookmarks, title: "Bookmarks", active: app.interface.rightPanel == .queue(.bookmarks)) {
                app.interface.toggleQueuePanel(.bookmarks)
            }
        default:
            if let command = control.command {
                MXRPlayerIconButton(icon, title: control.title, active: active,
                                    highlightsActive: control != .sidebarToggle || colorScheme != .light,
                                    box: buttonBox) { app.perform(command) }
                    .disabled(!app.canPerform(command) || (control == .record && !app.capabilities.hasRecording))
            }
        }
    }

    private func title(_ text: String, dragsWindow: Bool = false, truncation: Text.TruncationMode = .middle) -> some View {
        Text(text).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
            .lineLimit(1).truncationMode(truncation).clipped()
            // Titles are part of the window drag region (WT-10); in Customize they stay draggable items.
            .allowsHitTesting(!dragsWindow || app.interface.isCustomizing)
    }
    private var folderChip: some View {
        Button {
            if app.interface.library == .compact {
                app.interface.library = .hidden
                return
            }
            if let folder = app.player.media?.folder { app.library.navigate(to: .folder(folder.id)) }
            else { app.library.select(app.player.isAudioOnly ? .music : .videos) }
            app.interface.library = .compact
        } label: {
            HStack(spacing: Theme.Metric.Window.folderChip.gap) {
                MXRIcon(.folder).frame(width: MXRPlayerMetrics.headerIcon.width, height: MXRPlayerMetrics.headerIcon.height)
                // Takes exactly the width the row gives it (down to the icon alone, A-07).
                title(MXRControlTitles.folderChip(folder: app.player.media?.folder, audioOnly: app.player.isAudioOnly), truncation: .tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading).clipped()
            }.padding(.trailing, Theme.Metric.Window.folderChip.padding.trailing)
                .frame(height: Theme.Metric.Window.folderChip.height)
        }.buttonStyle(.plain).clipped().help("Open containing folder").accessibilityLabel("Open containing folder")
    }
    private var buttonBox: Theme.Box {
        switch control {
        case .previous, .next, .backward10, .forward10, .backward15, .forward15: Theme.Metric.ControlBar.prevNextCell
        // 247:466 is the top bar's window-control cell; in a control-bar row the button is an ordinary
        // bar icon (19m27.6: queue and fullscreen glyphs 50 pt apart, as Player - customize-7 draws them).
        case .fullscreen: inTopBar ? Theme.Metric.Window.windowControlCell : Theme.Metric.ControlBar.iconButton
        case .sidebarToggle: MXRPlayerMetrics.headerIcon
        default: Theme.Metric.ControlBar.iconButton
        }
    }
    private var active: Bool {
        switch control {
        case .sidebarToggle: app.interface.library != .hidden
        case .fullscreen: app.player.isFullscreen
        case .audioTracks: app.interface.rightPanel == .tracks(.audio)
        case .subtitleTracks: app.interface.rightPanel == .tracks(.subtitles)
        case .playbackSettings, .rightSidebar: app.interface.isSidebarOpen
        case .queue: app.interface.isQueuePanelOpen
        case .repeatMode: app.queue.repeatMode != .off
        case .shuffle: app.queue.isShuffled
        case .record: app.player.isRecording
        case .favorite: app.player.media?.isFavorite ?? false
        default: false
        }
    }
    private var icon: MXRIcon.Name { control.barIcon }
}

private extension View {
    /// Adds a tooltip only when there is text for it; network media has no file name.
    @ViewBuilder func mxrHelp(_ text: String?) -> some View {
        if let text, !text.isEmpty { help(text) } else { self }
    }
}
