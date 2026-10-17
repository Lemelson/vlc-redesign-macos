import MXRCore
import MXRDesign
import SwiftUI

public struct MXRSettingsSidebarView: View {
    public let tab: SidebarTab
    @Environment(InterfaceModel.self) private var ui
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var presetsOpen = false
    public init(tab: SidebarTab = .playback) { self.tab = tab }
    public var body: some View {
        let box = Theme.Metric.SidePanels.settingsSidebar
        GeometryReader { geometry in
            let height = min(box.height, geometry.size.height)
            let footer = SidebarFooterLayout(panelHeight: height)
            let bodyHeight = max(0, height - Theme.Metric.SidePanels.tabStrip.height - box.gap)
            // 5187:24308: the Playback tab has no preset footer. Elsewhere the footer yields to the
            // settings when the window is too short to show both (P17).
            let showsFooter = tab != .playback && bodyHeight - footer.height - box.gap >= PanelMetric.footerMinimumContentHeight
            PanelSurface {
            VStack(spacing: box.gap) {
                PanelTabStrip(tabs: SidebarTab.allCases, selected: tab, title: { $0.title }, icon: {
                    switch $0 { case .playback: .playback; case .video: .video; case .audio: .audio; case .subtitles: .subtitles }
                }, width: {
                    ($0 == .playback || $0 == .subtitles) ? Theme.Metric.SidePanels.tabCell4wide.width : Theme.Metric.SidePanels.tabCell4narrow.width
                }) { ui.selectTab(.sidebar($0)) }
                ScrollView {
                    VStack(spacing: 0) {
                        switch tab {
                        case .playback: PlaybackSidebarContent()
                        case .video: VideoSidebarContent()
                        case .audio: AudioSidebarContent()
                        case .subtitles: SubtitleSidebarContent()
                        }
                    }.frame(maxWidth: .infinity)
                }.scrollIndicators(.hidden)
                    .frame(height: max(0, bodyHeight - (showsFooter ? footer.height + box.gap : 0)))
                if showsFooter { SidebarPresetFooter(tab: tab, layout: footer, presetsOpen: presetsBinding) }
            }
            .overlay(alignment: .bottom) {
                if showsFooter && presetsOpen {
                    ZStack(alignment: .bottom) {
                        // A click anywhere else in the sidebar closes the list (D024).
                        Color.clear.contentShape(Rectangle()).onTapGesture { presetsBinding.wrappedValue = false }
                        MXRSidebarPresetList(close: { presetsBinding.wrappedValue = false })
                            .frame(maxHeight: max(0, bodyHeight - PanelSpace.xl), alignment: .bottom)
                            .padding(.horizontal, PanelSpace.xl)
                            .padding(.bottom, footer.presetBottomInset)
                            .mxrPopupTransition(from: .bottom, reduceMotion: reduceMotion)
                    }
                }
            }
            }.frame(width: min(box.width, geometry.size.width), height: height)
        }.frame(maxWidth: box.width, maxHeight: box.height)
        .onChange(of: tab) { presetsOpen = false }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tab.title) settings")
    }

    private var presetsBinding: Binding<Bool> {
        Binding(get: { presetsOpen }, set: { open in
            withAnimation(reduceMotion ? nil : .easeOut(duration: open ? MXRPopupMotion.insertion : MXRPopupMotion.removal)) {
                presetsOpen = open
            }
        })
    }
}

/// Gallery and review aid: one sidebar tab's content laid out at full height on the panel
/// surface, unscrolled, so sections below the fold (the Subtitles Appearance rows, 800:1126)
/// can be compared without scrolling. The shipping sidebar is ``MXRSettingsSidebarView``.
public struct MXRSidebarContentPreview: View {
    let tab: SidebarTab
    public init(tab: SidebarTab) { self.tab = tab }
    public var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                switch tab {
                case .playback: PlaybackSidebarContent()
                case .video: VideoSidebarContent()
                case .audio: AudioSidebarContent()
                case .subtitles: SubtitleSidebarContent()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// 763:2037 footer: the preset selector over "Open Advanced Settings"; compact in short windows.
private struct SidebarFooterLayout {
    let compact: Bool
    init(panelHeight: CGFloat) {
        compact = panelHeight < PanelMetric.compactFooterPanelHeight
    }
    var height: CGFloat { compact ? PanelMetric.compactFooterHeight : PanelMetric.footerHeight }
    var presetHeight: CGFloat { compact ? PanelMetric.compactPresetHeight : PanelMetric.presetHeight }
    var buttonHeight: CGFloat { compact ? PanelMetric.compactFooterButtonHeight : Theme.Metric.SidePanels.footerButton.height }
    var gap: CGFloat { compact ? Theme.Spacing.gap4 : Theme.Spacing.gap10 }
    var verticalPadding: CGFloat { compact ? Theme.Spacing.gap10 : PanelSpace.xl }
    /// Distance from the panel bottom to the selector's bottom edge, where the list is anchored.
    var presetBottomInset: CGFloat { verticalPadding + buttonHeight + gap }
}

private struct SidebarPresetFooter: View {
    let tab: SidebarTab
    let layout: SidebarFooterLayout
    @Binding var presetsOpen: Bool
    @Environment(AppModel.self) private var app
    @Environment(InterfaceModel.self) private var ui
    var body: some View {
        VStack(spacing: 0) {
            PanelDivider(consumesHeight: false)
            VStack(spacing: layout.gap) {
                Button { presetsOpen.toggle() } label: {
                    HStack {
                        Text(app.activePreset.name).lineLimit(1)
                        Spacer(minLength: PanelSpace.xs)
                        MXRIcon(.chevronUp)
                    }
                    .foregroundStyle(Theme.Color.fgA2)
                    .padding(.horizontal, PanelSpace.lg) // 2372:8836: 2 + 14 pt insets.
                    .frame(height: layout.presetHeight)
                    .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Playback preset").accessibilityValue(app.activePreset.name)
                .accessibilityHint("Shows the saved presets")
                Button { ui.present(.settings(categoryID: tab.rawValue)) } label: {
                    HStack(spacing: Theme.Spacing.gap6) {
                        MXRIcon(.settings, size: PanelMetric.tabIconSize, tint: nil)
                        Text("Open Advanced Settings")
                    }
                    .frame(maxWidth: .infinity).frame(height: layout.buttonHeight)
                }.buttonStyle(PanelButtonStyle(kind: .link))
            }
            .padding(.horizontal, PanelSpace.xl).padding(.vertical, layout.verticalPadding)
        }.frame(height: layout.height)
            .background {
                MXRBackdropSurface(tint: Theme.Color.bgB1Transparent) // 812:1580, 763:2037: BACKGROUND_BLUR 50.
            }
    }
}

/// 2372:8838 / video 07m58.9: "+ New Custom Preset" first, then the presets, each with a ⋯ menu,
/// the current one checked on a highlighted row. Opens upward over the selector.
public struct MXRSidebarPresetList: View {
    let close: () -> Void
    public init(close: @escaping () -> Void = {}) { self.close = close }
    @Environment(AppModel.self) private var app
    @State private var actionsFor: String?
    @State private var asksName = false
    @State private var name = ""
    @State private var renameID: String?
    @State private var deleting: PlaybackPreset?
    @State private var highlighted: Int?
    @FocusState private var focused: Bool

    /// The default preset, then the saved ones in creation order; the current preset comes last,
    /// over the selector, like a Mac pop-up (2372:8839 Default ✓ and 07m58.9 "The Wand" ✓ both sit there).
    private var presets: [PlaybackPreset] {
        let current = app.activePreset.id
        let all = app.presets.presets
        let ordered = all.filter { $0.id == PlaybackPreset.defaultID } + all.filter { $0.id != PlaybackPreset.defaultID }
        return ordered.filter { $0.id != current } + ordered.filter { $0.id == current }
    }

    public var body: some View {
        // The card hugs its rows and scrolls only when the window is too short for them.
        ViewThatFits(in: .vertical) {
            rows
            // Scrolled to the end: the current preset sits next to the selector.
            ScrollView { rows }.scrollIndicators(.hidden).defaultScrollAnchor(.bottom)
        }
        .mxrTextStyle(Theme.Font.body) // 2372:8840: Inter 14/400, also outside the sidebar's surface
        // The shadow belongs to the card shape only: on the whole view SwiftUI would also shade
        // every row highlight and title onto the card (2372:8838 has none inside).
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgA4)
                .mxrShadow(Theme.Effect.presetListShadow)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onExitCommand(perform: close)
        .onMoveCommand { direction in
            let count = presets.count + 1
            switch direction {
            case .up: highlighted = max(0, (highlighted ?? count) - 1)
            case .down: highlighted = min(count - 1, (highlighted ?? -1) + 1)
            default: break
            }
        }
        .onKeyPress(.return) {
            guard let highlighted else { return .ignored }
            if highlighted == 0 { beginNew() } else { choose(presets[highlighted - 1]) }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Presets")
        .alert(renameID == nil ? "New Custom Preset" : "Rename Preset", isPresented: $asksName) {
            TextField("Preset name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                if let renameID { app.presets.rename(id: renameID, to: text) }
                else { _ = app.createPreset(named: text) }
                close()
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            if renameID == nil { Text("Saves the current subtitle, audio and video settings for this show.") }
        }
        .alert("Delete “\(deleting?.name ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { app.presets.delete(id: deleting.id) }
                deleting = nil; actionsFor = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Shows that use this preset go back to the default preset.")
        }
    }

    private var rows: some View {
        let current = app.activePreset.id
        return VStack(spacing: PanelMetric.presetListPadding) {
            Button { beginNew() } label: {
                row(icon: .add, title: "New Custom Preset", iconTint: Theme.Color.fgA3, titleColor: Theme.Color.fgA3)
            }
            .buttonStyle(PanelButtonStyle(kind: .row))
            .background(highlightFill(index: 0))
            ForEach(Array(presets.enumerated()), id: \.element.id) { index, preset in
                presetRow(preset, selected: preset.id == current, index: index + 1)
                if actionsFor == preset.id {
                    actionRow(icon: .edit, title: "Rename…") { beginRename(preset) }
                    actionRow(icon: .remove, title: "Delete…") { deleting = preset }
                }
            }
        }
        .padding(PanelMetric.presetListPadding)
    }

    private func presetRow(_ preset: PlaybackPreset, selected: Bool, index: Int) -> some View {
        HStack(spacing: Theme.Spacing.gap10) {
            // 2372:8839: the built-in preset has no ⋯ (it cannot be renamed or deleted) and no empty
            // icon slot either; its name starts at the row's 16 pt inset.
            if preset.id != PlaybackPreset.defaultID {
                Button { actionsFor = actionsFor == preset.id ? nil : preset.id } label: {
                    MXRIcon(.more, tint: Theme.Color.fgA3)
                }
                .buttonStyle(PanelButtonStyle(kind: .icon))
                .help("Preset actions")
                .accessibilityLabel("Actions for \(preset.name)")
            }
            Button { choose(preset) } label: {
                HStack(spacing: Theme.Spacing.gap10) {
                    Text(preset.name).foregroundStyle(Theme.Color.fgA2).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected { MXRIcon(.check, state: .active) }
                }.frame(maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preset.name)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, PanelSpace.md + Theme.Spacing.gap2)
        .frame(height: PanelMetric.presetRowHeight)
        .background(PresetRowHover(selected: selected || highlighted == index))
    }

    private func actionRow(icon: MXRIcon.Name, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            row(icon: icon, title: title, iconTint: Theme.Color.fgA3, titleColor: Theme.Color.fgA2)
                .padding(.leading, Theme.Metric.iconSize + Theme.Spacing.gap10)
        }.buttonStyle(PanelButtonStyle(kind: .row))
    }

    private func row(icon: MXRIcon.Name, title: String, iconTint: ThemeColor, titleColor: ThemeColor) -> some View {
        HStack(spacing: Theme.Spacing.gap10) {
            MXRIcon(icon, tint: iconTint)
            Text(title).foregroundStyle(titleColor).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelSpace.md + Theme.Spacing.gap2)
        .frame(height: PanelMetric.presetRowHeight)
    }

    private func highlightFill(index: Int) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgA2.opacity(highlighted == index ? 1 : 0))
    }

    private func choose(_ preset: PlaybackPreset) {
        app.selectPreset(preset)
        close()
    }
    private func beginNew() { name = ""; renameID = nil; asksName = true }
    private func beginRename(_ preset: PlaybackPreset) { name = preset.name; renameID = preset.id; asksName = true }
}

/// option 2107:5936 / 2107:5942: hover and selected rows share the BG/A2 fill.
private struct PresetRowHover: View {
    let selected: Bool
    @State private var hovered = false
    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.md)
            .fill(Theme.Color.bgA2.opacity(selected || hovered ? 1 : 0))
            .onHover { hovered = $0 }
    }
}

/// S17, video 09m17.5: the complete Playback tab. Rows and order follow the video; metrics follow
/// Figma 5187:24308 (toggle rows 52 pt, 220×48 dropdowns, 140×32 speed value, ticked slider).
private struct PlaybackSidebarContent: View {
    @Environment(PlayerModel.self) private var player
    @Environment(InterfaceModel.self) private var ui
    @Environment(AppModel.self) private var app
    /// D014: Core clamps rates to positive values, so Reverse is shown but unavailable.
    static let reverseUnavailable = "Reverse playback isn’t available: VLC can only play media forward."
    /// CMP-17: cue timings are read from subtitle files, so an embedded track explains the ⓘ
    /// instead of silently showing an empty timeline. Once on, the toggle stays usable to turn it off.
    private var subtitleTimelineUnavailable: String? {
        guard app.capabilities.supportsSubtitleTimeline else { return "This VLC build can’t read subtitle timings." }
        guard !ui.showSubtitleTimeline, let track = app.tracks.selectedTrack(of: .subtitle), !track.isExternal else { return nil }
        return "The subtitle timeline reads cue times from subtitle files (SRT, VTT, ASS); this track is embedded in the video."
    }
    var body: some View {
        @Bindable var ui = ui
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                PanelToggleRow(title: "Show Subtitle Timeline on Seekbar", isOn: $ui.showSubtitleTimeline, height: PanelMetric.toggleRowHeight,
                               unavailableReason: subtitleTimelineUnavailable)
                PanelToggleRow(title: "Show Waveform on Seekbar", isOn: $ui.showWaveform, height: PanelMetric.toggleRowHeight,
                               unavailableReason: app.capabilities.supportsWaveform ? nil : "This VLC build can’t analyze audio for a waveform.")
                PanelToggleRow(title: "Show Metadata", isOn: $ui.showMetadata, height: PanelMetric.toggleRowHeight)
                PanelToggleRow(title: "Reverse", isOn: .constant(false), height: PanelMetric.toggleRowHeight,
                               unavailableReason: Self.reverseUnavailable)
            }
            .padding(.top, PanelMetric.settingsSectionPadding) // 5187:24486
            PanelDropdownRow(title: "Sleep Timer", selected: player.sleepTimer.title, choices: SleepTimer.allCases.map { value in
                PanelChoice(id: value.rawValue, title: value.title) { player.setSleepTimer(value) }
            }, height: PanelMetric.dropdownSize.height)
            .padding(.top, Theme.Spacing.gap10).padding(.bottom, PanelSpace.xl) // 5187:24532
            PanelDropdownRow(title: "Audio Visualizer", selected: player.audioVisualization.title, choices: AudioVisualization.allCases.map { value in
                PanelChoice(id: value.rawValue, title: value.title) { player.setAudioVisualization(value) }
            }, height: PanelMetric.dropdownSize.height)
            .padding(.bottom, PanelSpace.xl) // 5187:24514
            VStack(spacing: 0) {
                PanelFieldRow(title: "Speed", value: String(format: "%gx", player.rate), commit: { text in
                    if let value = panelNumber(text.replacingOccurrences(of: "x", with: "")) { player.setRate(value) }
                }, height: PanelMetric.compactFieldRowHeight, style: .filled) // 5187:24540/24542
                PanelSlider(title: "Playback speed", value: Binding(get: { player.rate }, set: { player.setRate($0) }), range: 0.25...2,
                            labels: ["0.25", "0.5", "0.75", "1", "1.25", "1.5", "1.75", "2"], step: 0.05, ticks: true,
                            labelsBelowThumb: true)
                    .padding(.vertical, PanelSpace.xs) // 5187:24544
            }
            .disabled(!player.canChangeRate)
            .padding(.bottom, PanelMetric.speedSectionBottomPadding) // 5187:24539
        }
        .padding(.horizontal, PanelSpace.xl)
        // 5187:24342/24374: only the Playback tab draws a full-width hairline at the top of its
        // content, under the tab strip (y 51); the other tabs start with their "Defaults" header.
        .overlay(alignment: .top) { PanelDivider(consumesHeight: false) }
    }
}

struct SubtitleSidebarContent: View {
    @Environment(TracksModel.self) private var tracks
    var body: some View {
        VStack(spacing: 0) {
            PanelSectionTitle(title: "Defaults")
            defaults
            PanelDivider(consumesHeight: false)
            PanelSectionTitle(title: "Synchronization")
            synchronization
            PanelDivider(consumesHeight: false)
            PanelSectionTitle(title: "Appearance")
            appearance
        }
    }
    private var defaults: some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            PanelFieldRow(title: "Subtitle Track", value: tracks.trackDefaults.subtitleTrack.map(String.init) ?? "Automatic") { text in
                tracks.updateTrackDefaults { $0.subtitleTrack = Int(text).flatMap { $0 > 0 ? $0 : nil } }
            }
            PanelFieldRow(title: "Subtitle Language", value: tracks.trackDefaults.subtitleLanguage ?? "Automatic") { text in
                tracks.updateTrackDefaults { $0.subtitleLanguage = text.isEmpty || text == "Automatic" ? nil : text }
            }
        }.padding(.horizontal, PanelSpace.xl).padding(.vertical, PanelMetric.settingsSectionPadding)
    }
    private var synchronization: some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            delayControl(title: "Subtitle Track Delay", value: tracks.subtitleDelay.seconds) { tracks.setSubtitleDelay(.seconds($0)) }
            // 804:1170: "1.000 fps" with the thumb at the start of the 1…100 fps range.
            PanelFieldRow(title: "Subtitle Speed", value: String(format: "%.3f fps", tracks.subtitleSpeed), commit: { text in
                if let value = panelNumber(text) { tracks.setSubtitleSpeed(value) }
            }, height: PanelMetric.fieldRowHeight)
            PanelSlider(title: "Subtitle speed", value: Binding(get: { tracks.subtitleSpeed }, set: { tracks.setSubtitleSpeed($0) }),
                        range: TracksModel.subtitleSpeedRange, valueDescription: String(format: "%.3f fps", tracks.subtitleSpeed))
            PanelFieldRow(title: "Subtitle Duration Factor", value: String(format: "%.3f", tracks.subtitleDurationFactor), commit: { text in
                if let value = panelNumber(text) { tracks.setSubtitleDurationFactor(max(0, value)) }
            }, height: PanelMetric.fieldRowHeight) // 804:1179
            PanelSlider(title: "Subtitle duration factor", value: Binding(get: { tracks.subtitleDurationFactor }, set: { tracks.setSubtitleDurationFactor($0) }), range: 0...10)
        }.padding(.horizontal, PanelSpace.xl).padding(.top, PanelMetric.settingsSectionPadding).padding(.bottom, PanelMetric.settingsBottomPadding)
    }
    private var appearance: some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            // 2255:9846: 10 pt above and 6 pt below the toggle, so it sits 2 pt below the row's centre.
            PanelToggleRow(title: "Embedded Sub Format", isOn: style(\.useEmbeddedStyles),
                           height: PanelMetric.settingsRowHeight - Theme.Spacing.gap4)
                .padding(.top, Theme.Spacing.gap4)
            PanelFieldRow(title: "Subtitle Font", value: tracks.subtitleStyle.fontFamily.isEmpty ? "System" : tracks.subtitleStyle.fontFamily) { text in
                tracks.updateSubtitleStyle { $0.fontFamily = text == "System" ? "" : text }
            }
            colorField("Text Color", keyPath: \.textColor)
            colorField("Outline Color", keyPath: \.outlineColor)
            // 2199:9211, 07m52.9: a field-only 48 pt row (D033: no slider here).
            PanelFieldRow(title: "Subtitle Offset", value: "\(tracks.subtitleStyle.offset)px") { text in
                if let value = Int(text.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)) { tracks.updateSubtitleStyle { $0.offset = max(0, value) } }
            }
            HStack {
                Text("Size Values").foregroundStyle(Theme.Color.fgA3)
                Spacer()
                HStack(spacing: Theme.Spacing.gap2) {
                    sizeMode(.relative, title: "Relative")
                    sizeMode(.pixels, title: "Pixels")
                }.padding(Theme.Spacing.gap2).frame(width: PanelMetric.sizeModeSize.width, height: PanelMetric.sizeModeSize.height) // 804:1229
                    .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
            }.padding(.leading, PanelSpace.xs).frame(height: PanelMetric.sizeModeRowHeight) // 800:1136
            // VIDEO_BREAKDOWN §329: Relative mode shows word sliders (800:1126: 804:1341, 804:1342,
            // 848:1686); Pixels mode shows exact px fields (07m52.9).
            if tracks.subtitleStyle.sizeMode == .pixels {
                pixelField("Font Size", value: tracks.subtitleStyle.pixelSize) { style, size in style.pixelSize = min(max(size, 6), 200) }
                pixelField("Outline Thickness", value: tracks.subtitleStyle.outline.rawValue) { style, pixels in style.outline = .nearest(pixels: pixels) }
                PanelFieldRow(title: "Background Opacity", value: String(format: "%.0f%%", tracks.subtitleStyle.backgroundOpacity * 100)) { text in
                    if let value = panelNumber(text.replacingOccurrences(of: "%", with: "")) { tracks.updateSubtitleStyle { $0.setBackgroundOpacity(value / 100) } }
                }
            } else {
                wordSlider("Font Size", choices: SubtitleRelativeSize.sliderOrder, keyPath: \.relativeSize)
                wordSlider("Outline Thickness", choices: Array(SubtitleOutline.allCases), keyPath: \.outline)
                PanelValueSliderRow(title: "Background Opacity", value: String(format: "%.0f %%", tracks.subtitleStyle.backgroundOpacity * 100),
                                    position: Binding(get: { tracks.subtitleStyle.backgroundOpacity },
                                                      set: { value in tracks.updateSubtitleStyle { $0.setBackgroundOpacity(value) } }),
                                    range: 0...1, step: 0.1) // 848:1686: eleven 10 % stops
            }
            // CMP-18: no Position row. VLC 4 places primary subtitles at the bottom only;
            // Subtitle Offset (sub-margin) raises them.
            PanelToggleRow(title: "Bold", isOn: style(\.bold))
            PanelToggleRow(title: "Shadow", isOn: style(\.shadow))
        }.padding(.horizontal, PanelSpace.xl).padding(.vertical, PanelMetric.settingsSectionPadding)
    }
    private func style<Value>(_ path: WritableKeyPath<SubtitleStyle, Value>) -> Binding<Value> {
        Binding(get: { tracks.subtitleStyle[keyPath: path] }, set: { value in tracks.updateSubtitleStyle { $0[keyPath: path] = value } })
    }
    private func sizeMode(_ mode: SubtitleSizeMode, title: String) -> some View {
        Button { tracks.updateSubtitleStyle { $0.sizeMode = mode } } label: {
            Text(title).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(tracks.subtitleStyle.sizeMode == mode ? Theme.Color.accentMain : Theme.Color.fgA3)
                .background(tracks.subtitleStyle.sizeMode == mode ? Theme.Color.bgAccentBright : Theme.Color.bgA4, in: .rect(cornerRadius: Theme.Radius.md))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(tracks.subtitleStyle.sizeMode == mode ? .isSelected : [])
    }
    /// A Pixels-mode "Npx" field (07m52.9); `apply` clamps or maps the typed integer.
    private func pixelField(_ title: String, value: Int, apply: @escaping (inout SubtitleStyle, Int) -> Void) -> some View {
        PanelFieldRow(title: title, value: "\(value)px") { text in
            if let number = Int(text.replacingOccurrences(of: "px", with: "").trimmingCharacters(in: .whitespaces)) {
                tracks.updateSubtitleStyle { apply(&$0, number) }
            }
        }
    }
    /// A Relative-mode word slider: the choice as text over one ticked stop per choice, in `choices`
    /// order (804:1341/1342).
    private func wordSlider<Choice: Equatable & SubtitleWordChoice>(_ title: String, choices: [Choice],
                                                                    keyPath: WritableKeyPath<SubtitleStyle, Choice>) -> some View {
        let selected = tracks.subtitleStyle[keyPath: keyPath]
        return PanelValueSliderRow(title: title, value: selected.title,
                                   position: Binding(get: { Double(choices.firstIndex(of: tracks.subtitleStyle[keyPath: keyPath]) ?? 0) },
                                                     set: { index in
                                                         let i = min(max(Int(index.rounded()), 0), choices.count - 1)
                                                         tracks.updateSubtitleStyle { $0[keyPath: keyPath] = choices[i] }
                                                     }),
                                   range: 0...Double(choices.count - 1), step: 1)
    }
    private func colorField(_ title: String, keyPath: WritableKeyPath<SubtitleStyle, MXRCore.RGBColor>) -> some View {
        PanelColorField(title: title, color: style(keyPath))
    }
}

/// Relative-mode subtitle values named by a word.
protocol SubtitleWordChoice { var title: String { get } }
extension SubtitleRelativeSize: SubtitleWordChoice {}
extension SubtitleOutline: SubtitleWordChoice {}

@MainActor
func delayControl(title: String, value: Double, trackHeight: CGFloat = PanelMetric.sliderTrackHeight, set: @escaping @MainActor @Sendable (Double) -> Void) -> some View {
    VStack(spacing: PanelMetric.settingsRowGap) {
        PanelFieldRow(title: title, value: String(format: "%.3f s", value), commit: { text in
            if let value = panelNumber(text) { set(value) }
        }, height: PanelMetric.fieldRowHeight) // 767:2197
        PanelSlider(title: title, value: Binding(get: { value }, set: set), range: -10...10, center: 0, labels: ["-10 s", "0 s", "+10 s"], step: 0.05, trackHeight: trackHeight)
    }
}
