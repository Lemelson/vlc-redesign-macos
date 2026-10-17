import MXRCore
import MXRDesign
import SwiftUI

/// The right-side panel family. The player shell supplies positioning; this view follows the
/// single open panel in InterfaceModel, so track/preferences/queue transitions stay exclusive.
public struct MXRRightPanelView: View {
    @Environment(InterfaceModel.self) private var ui
    public init() {}
    public var body: some View {
        Group {
            switch ui.rightPanel {
            case .tracks(let tab): MXRTrackPopoverView(tab: tab)
            case .sidebar(let tab): MXRSettingsSidebarView(tab: tab)
            case .queue(let tab): MXRQueuePanelView(tab: tab)
            case nil: EmptyView()
            }
        }
        .onExitCommand { ui.closeRightPanel() }
    }
}

public struct MXRTrackPopoverView: View {
    public let tab: TrackPanelTab
    @Environment(TracksModel.self) private var tracks
    @Environment(InterfaceModel.self) private var ui
    @Environment(PlayerModel.self) private var player
    @Environment(AppModel.self) private var app
    public init(tab: TrackPanelTab = .subtitles) { self.tab = tab }
    private var kind: TrackKind {
        switch tab { case .video: .video; case .audio: .audio; case .subtitles: .subtitle }
    }
    private var editSubtitlesScope: AddSubtitlesScope { player.media?.folder != nil ? .folder : .file }
    private var editSubtitlesLabel: String {
        editSubtitlesScope == .folder ? "Edit subtitles for this folder" : "Edit subtitles for this video"
    }
    public var body: some View {
        let popup = Theme.Metric.SidePanels.tracksPopup
        PanelSurface {
            VStack(spacing: popup.gap) {
                PanelTabStrip(tabs: TrackPanelTab.allCases, selected: tab, title: { $0.title }, icon: {
                    switch $0 { case .video: .video; case .audio: .audio; case .subtitles: .subtitles }
                }, width: { _ in Theme.Metric.SidePanels.tabCell3.width }) { ui.selectTab(.tracks($0)) }
                ScrollView {
                    // 491:2243 / 496:2523: the sections sit 1 pt apart like the popup's own rows, and the
                    // divider (496:2652) is a zero-height line in its own 1 pt-spaced slot.
                    VStack(spacing: popup.gap) {
                        sectionHeader("Embedded Tracks")
                        VStack(spacing: PanelMetric.gap) {
                            trackRow("None", selected: tracks.isNoneSelected(kind)) { tracks.selectNone(kind) }
                            ForEach(tracks.embeddedTracks(of: kind)) { track in
                                trackRow(track.name, selected: track.isSelected) { tracks.select(track) }
                            }
                        }
                        .padding(.horizontal, Theme.Metric.SidePanels.listContainer.padding.leading)
                        .padding(.bottom, PanelMetric.trackBottomPadding)
                        if tab == .audio {
                            PanelDivider(consumesHeight: false)
                            sectionHeader("Output Device") {
                                PanelIconButton(icon: .refresh, label: "Refresh audio devices", width: Theme.Metric.iconSize, tint: Theme.Color.fgA3) { tracks.refreshAudioDevices() }
                            }
                            VStack(spacing: PanelMetric.gap) {
                                ForEach(tracks.audioDevices) { device in
                                    trackRow(device.name, selected: tracks.currentAudioDeviceID == device.id) { tracks.selectAudioDevice(device) }
                                }
                            }.padding(.horizontal, Theme.Metric.SidePanels.listContainer.padding.leading)
                        } else if tab == .subtitles {
                            PanelDivider(consumesHeight: false)
                            sectionHeader("External Tracks") {
                                // §04/§06 (D033): + opens Add Subtitles on "To This File" (video 06m08.5); the
                                // pencil edits the matches of the whole folder, like the library's "Edit
                                // Subtitle Tracks", and of this file outside the library.
                                PanelIconButton(icon: .edit, label: editSubtitlesLabel, width: Theme.Metric.iconSize, tint: Theme.Color.fgA3) {
                                    app.presentAddSubtitles(media: [], scope: editSubtitlesScope)
                                }.disabled(player.media == nil)
                                PanelIconButton(icon: .add, label: "Add subtitles to this video", width: Theme.Metric.iconSize, tint: Theme.Color.fgA3) {
                                    app.presentAddSubtitles(media: [], scope: .file)
                                }.disabled(player.media == nil)
                            }
                            VStack(spacing: PanelMetric.gap) {
                                ForEach(tracks.externalTracks(of: kind)) { track in
                                    trackRow(track.name, selected: track.isSelected) { tracks.select(track) }
                                }
                            }.padding(.horizontal, Theme.Metric.SidePanels.listContainer.padding.leading)
                        }
                    }
                }.scrollIndicators(.hidden)
                Button { ui.showPreferences(for: tab) } label: {
                    Text("Show Preferences")
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Metric.SidePanels.footerButton.height)
                }
                .buttonStyle(PanelButtonStyle(kind: .footer)) // 500:3062 default, 500:3064 hover.
                .padding(Theme.Metric.SidePanels.footer.padding.edgeInsets)
                .frame(height: Theme.Metric.SidePanels.footer.height)
            }
        }.frame(maxWidth: popup.width, maxHeight: popup.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tab.title) tracks")
    }

    /// 2410:13482 / 496:2631: the actions are 24 pt FG/A3 icons 20 pt apart (6059:13202), flush with the
    /// row's 28 pt inset.
    private func sectionHeader<Actions: View>(_ title: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: PanelSpace.xl) {
            Text(title).foregroundStyle(Theme.Color.fgA3)
            Spacer()
            actions()
        }
        .padding(.horizontal, Theme.Metric.SidePanels.sectionHeaderRow.padding.leading)
        .frame(height: Theme.Metric.SidePanels.sectionHeaderRow.height)
    }
    private func sectionHeader(_ title: String) -> some View { sectionHeader(title) { EmptyView() } }
    private func trackRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Metric.SidePanels.listRow.gap) {
                MXRIcon(.check, state: selected ? .active : .default)
                    .frame(width: Theme.Metric.SidePanels.listRow.height, height: Theme.Metric.SidePanels.listRow.height)
                Text(title).foregroundStyle(Theme.Color.fgA2).lineLimit(1)
                Spacer(minLength: 0)
            }.frame(height: Theme.Metric.SidePanels.listRow.height)
        }
        .buttonStyle(PanelButtonStyle(kind: .row))
        .help(title)
        .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
