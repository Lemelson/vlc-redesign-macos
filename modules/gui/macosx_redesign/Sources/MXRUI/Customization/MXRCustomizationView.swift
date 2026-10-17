import MXRCore
import MXRDesign
import SwiftUI

/// S66: the central tile palette. The host supplies the dimmed player and the editable bars.
public struct MXRCustomizationView: View {
    @Environment(AppModel.self) private var app
    @State private var isRemovalTarget = false

    public init() {}
    public static var preferredSize: CGSize { Theme.Metric.Customization.panel.size }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                palette(width: geometry.size.width,
                        height: max(0, geometry.size.height - Theme.Metric.Customization.header.height - Theme.Metric.dialogFooterHeight))
                footer
            }
        }
        .frame(maxWidth: Self.preferredSize.width, maxHeight: Self.preferredSize.height)
        .background { MXRBackdropSurface(tint: Theme.Color.bgB1Transparent,
                                         cornerRadius: Theme.Metric.Customization.panel.radius ?? Theme.Radius.lg) }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.Customization.panel.radius ?? Theme.Radius.lg))
        .customizationShadow(Theme.Effect.menuShadow,
                             cornerRadius: Theme.Metric.Customization.panel.radius ?? Theme.Radius.lg)
        .onExitCommand { app.endCustomizing(save: false) }
    }

    private var header: some View {
        let box = Theme.Metric.Customization.header
        return VStack(spacing: box.gap) {
            HStack {
                Text("Customize Player").mxrTextStyle(.body).foregroundStyle(Theme.Color.fgA1)
                    .padding(.leading, box.padding.leading)
                Spacer()
                Button { app.endCustomizing(save: false) } label: {
                    MXRIcon(.close).frame(width: Theme.Metric.iconButtonHeight, height: Theme.Metric.iconButtonHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel customization")
            }
            .frame(height: Theme.Metric.iconButtonHeight)
            Text("Drag items around and out of the box below to re-order them. Drag items into the box to remove them from the player.")
                .mxrTextStyle(.body)
                .foregroundStyle(Theme.Color.fgA3)
                .frame(maxWidth: .infinity, minHeight: Theme.Metric.iconButtonHeight, alignment: .leading)
                .padding(.horizontal, box.padding.leading)
        }
        .padding(box.padding.edgeInsets)
        .frame(height: box.height)
        .background(Theme.Color.bgB2)
    }

    private func palette(width: CGFloat, height: CGFloat) -> some View {
        let controls = MXRCustomizationPalette.controls(for: app.playerLayout, kind: app.layoutKind)
        let gridWidth = max(Theme.Metric.Customization.tile.width,
                            width - Theme.Metric.Customization.body.padding.leading - Theme.Metric.Customization.body.padding.trailing)
        let columns = max(1, min(Int(Theme.Metric.Customization.gridColumns),
            Int((gridWidth + Theme.Metric.Customization.grid.gap) /
                (Theme.Metric.Customization.tile.width + Theme.Metric.Customization.grid.gap))))
        let rows = stride(from: 0, to: controls.count, by: columns).map {
            Array(controls[$0..<min($0 + columns, controls.count)])
        }
        let overflows = MXRCustomizationPalette.overflows(rows: rows, available: height)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Theme.Metric.Customization.gridRowGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: Theme.Metric.Customization.grid.gap) {
                        ForEach(row, id: \.self) { control in
                            MXRCustomizationTile(control: control)
                                .draggable(MXRLayoutDragPayload.tile(control))
                                .mxrKeyboardFocusable(cornerRadius: Theme.Radius.lg) // no system focus ring (C1, D028)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(control.title)
                                .accessibilityHint("Drag to a player bar to add this control")
                                .accessibilityAction(named: "Add to control bar") {
                                    _ = MXRLayoutDragPayload.tile(control).place(in: .bottom(0),
                                          at: app.playerLayout.bottom.first?.count ?? 0, app: app)
                                }
                        }
                    }
                }
            }
            .frame(width: gridWidth, alignment: .leading)
            .padding(Theme.Metric.Customization.body.padding.edgeInsets)
        }
        // SD-M2: when the tiles do not fit, the palette still uses all its height, the last visible
        // row fades out at the bottom edge (no hard-cut labels, no dead band) and the scroll
        // indicator stays visible, so it is clear that more tiles follow.
        .scrollIndicators(overflows ? .visible : .automatic)
        .scrollIndicatorsFlash(onAppear: overflows)
        .mask {
            if overflows {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: MXRCustomizationPalette.fadeHeight(available: height))
                }
            } else {
                Rectangle()
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .overlay {
            if isRemovalTarget {
                Rectangle().strokeBorder(Theme.Color.accentMain, lineWidth: Theme.Stroke.iconActive)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: MXRLayoutDragPayload.self) { items, _ in
            guard let item = items.first else { return false }
            return item.remove(from: app)
        } isTargeted: { isRemovalTarget = $0 }
    }

    private var footer: some View {
        HStack {
            MXRCustomizationButton(title: "Cancel") { app.endCustomizing(save: false) }
            Spacer()
            MXRCustomizationButton(title: "Save", primary: true, enabled: app.layouts.hasChanges) {
                app.endCustomizing(save: true)
            }
        }
        .padding(Theme.Spacing.gap20)
        .frame(height: Theme.Metric.dialogFooterHeight)
    }
}

private struct MXRCustomizationTile: View {
    let control: PlayerControl

    var body: some View {
        VStack(spacing: Theme.Spacing.gap16) {
            Group {
                if let icon = control.customizationIcon { MXRIcon(icon) }
                else { Color.clear }
            }
            .frame(width: iconSize.width, height: iconSize.height)
            .overlay(Rectangle().stroke(Theme.Color.fgA3,
                                       style: StrokeStyle(lineWidth: Theme.Stroke.hairline,
                                                          dash: Theme.Stroke.customizeOutlineDash)))
            Text(control.tileLabel)
                .mxrTextStyle(.body)
                .foregroundStyle(Theme.Color.fgA1)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Tiles hug their content as in Figma; the row (top-aligned HStack) takes the tallest one.
        .frame(width: Theme.Metric.Customization.tile.width,
               height: MXRCustomizationPalette.tileHeight(for: control), alignment: .top)
        .contentShape(Rectangle())
    }

    private var iconSize: CGSize { MXRCustomizationPalette.iconSize(for: control) }
}

struct MXRCustomizationButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.mxrAccent) private var accent
    let title: String
    var primary = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        let box = Theme.Metric.Controls.dialogButton
        Button(action: action) {
            Text(title).mxrTextStyle(.button)
                .foregroundStyle(buttonColor(primary ? Theme.Color.accentMain : Theme.Color.fgA1))
                .frame(width: box.width, height: box.height)
                .background(buttonColor(primary ? Theme.Color.bgAccentBright : Theme.Color.bgA3),
                            in: RoundedRectangle(cornerRadius: box.radius ?? Theme.Radius.lg))
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(MXRCustomizationButtonStyle())
        .disabled(!enabled)
    }

    private func buttonColor(_ token: ThemeColor) -> Color {
        let value = token.value(scheme: colorScheme, accent: accent)
        guard primary && !enabled else { return value.color }
        // Figma's disabled Save uses luminosity blend + 50% opacity (6587:18977).
        let luminosity = value.red * 0.3 + value.green * 0.59 + value.blue * 0.11
        return Theme.RGBA(red: luminosity, green: luminosity, blue: luminosity).color
    }
}

private struct MXRCustomizationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

extension PlayerControl {
    var tileLabel: String {
        switch self {
        case .playbackSpeed: "Playback\nSpeed"
        case .forward10: "Forward\n10s"
        case .backward10: "Backward\n10s"
        case .forward15: "Forward\n15s"
        case .backward15: "Backward\n15s"
        case .pictureInPicture: "Picture in\nPicture"
        case .rightSidebar: "Right\nSidebar"
        case .playlistName: "Playlist\nName"
        default: title
        }
    }

    var customizationIcon: MXRIcon.Name? {
        switch self {
        case .spacer: nil
        case .divider: .divider
        case .playbackSpeed: .speed
        case .forward10: .forward10Sec
        case .backward10: .backward10Sec
        case .forward15: .forward15Sec
        case .backward15: .backward15Sec
        case .stop: .stop
        case .repeatMode: .repeatRight
        case .shuffle: .shuffleRight
        case .record: .record
        case .snapshot: .snapshot
        case .pictureInPicture: .pip
        case .hdr: .hdr
        case .zoom: .zoom
        case .rightSidebar: .sidebarRight
        case .sidebarToggle: .sidebarLeft
        case .quit: .quit
        case .settings: .settings
        case .goHome: .home
        case .thumbnail: .thumbnail
        case .fileName, .artistName, .folderNameTile, .playlistName, .properties, .title: .info
        case .replay: .replay
        case .chapters: .chapters
        case .favorite: .favorite
        case .bookmark: .bookmark
        case .bookmarks: .bookmarks
        case .playlists: .playlist
        case .logo: .vlc
        case .menu: .more
        case .folderName: .folder
        case .fullscreen: .fullscreen
        case .previous: .previous
        case .playPause: .play
        case .next: .next
        case .currentTime, .duration, .seekBar: .playback
        case .volume: .volumeHigh
        case .audioTracks: .audio
        case .subtitleTracks: .subtitles
        case .playbackSettings: .playbackSettings
        case .queue: .lists
        }
    }
}
