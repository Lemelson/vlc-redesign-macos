import AppKit
import MXRCore
import MXRDesign
import SwiftUI

// Metrics missing from metrics.json, read directly from the named Figma nodes.
// Numeric ranges below come from the Core/VLC contracts, rather than visual metrics.
enum PanelSpace {
    static let xs = Theme.Spacing.gap4
    static let sm = Theme.Spacing.gap8
    static let md = Theme.Spacing.gap12
    static let lg = Theme.Spacing.gap16
    static let xl = Theme.Spacing.gap20
}

enum PanelMetric {
    static let tabIconSize: CGFloat = 20 // 2127:7638
    /// 5187:24309: tab titles need the full 400 pt strip; narrower panels show icons only.
    static let tabTitlesMinimumWidth: CGFloat = 360
    static let controlBorder: CGFloat = 2 // 4046:12353, input border
    static let gap: CGFloat = 12 // 463:847, queue row gap
    // 496:2540: the 138 pt list (three 32 pt rows, two 12 pt gaps) above the divider at y 251. The
    // Subtitles frame's 138.5 (491:2258) has no divider to sit on the pixel grid (D054).
    static let trackBottomPadding: CGFloat = 18
    static let sectionTitleHeight: CGFloat = 39 // 845:1677
    static let settingsRowHeight: CGFloat = 48 // 845:1598
    static let toggleRowHeight: CGFloat = 52 // 5187:24487: 32 pt toggle with 10 pt vertical padding
    static let settingsRowGap: CGFloat = 5 // 845:1597
    static let fieldSize = CGSize(width: 140, height: 36) // 4046:12353
    static let compactFieldHeight: CGFloat = 32 // 5187:24542 Speed field
    static let fieldRowHeight: CGFloat = 56 // 804:1170, 804:1179, 767:2197: value row above a slider
    static let valueTextRowHeight: CGFloat = 37 // 804:1329: plain-text value row above a word slider
    static let compactFieldRowHeight: CGFloat = 44 // 5187:24540 Speed row
    static let colorFieldTrailingInset: CGFloat = 34 // 4046:12374: 22 pt swatch + 12 pt inset
    static let colorSwatchSize: CGFloat = 22 // 4046:12377
    static let dropdownSize = CGSize(width: 220, height: 48) // 498:3013
    static let dropdownMinimumWidth: CGFloat = 120 // narrow panels keep the value readable
    static let dropdownLabelReserve: CGFloat = 140 // 5187:24533: label cell plus gap beside the 220 pt dropdown
    static let toggleSize = CGSize(width: 68, height: 32) // 536:1013
    static let toggleInset: CGFloat = 3 // 536:1010/1011: 3 pt outer insets and inner gap
    static let toggleKnobWidth: CGFloat = 26 // 536:1011
    static let sliderHeight: CGFloat = 24 // 804:1174
    static let sliderTrackHeight: CGFloat = 16 // 804:1175
    static let sliderHandleSize = CGSize(width: 8, height: 24) // 1905:7368
    static let sliderInset: CGFloat = 2 // 1905:7366
    /// 498:2969 / 536:1094: the selected Video or Audio tab's underline is 70 pt of the 85 pt cell,
    /// wider than the 61 pt content (5187:24319 is the unselected 61 pt one).
    static let selectedNarrowTabUnderlineInset: CGFloat = 7.5
    static let sliderLabelsGap: CGFloat = 10 // 1905:7365
    static let sliderTickSize = CGSize(width: 2, height: 6) // 5187:24550: 2 pt stroke, 6 pt tall
    static let footerHeight: CGFloat = 125 // 763:2037
    static let compactFooterHeight: CGFloat = 80 // compact windows: 32 pt preset + 24 pt link + paddings
    static let compactFooterPanelHeight: CGFloat = 400 // panels shorter than this use the compact footer
    static let compactPresetHeight: CGFloat = 32 // 5187:24542 field height reused by the compact preset
    static let compactFooterButtonHeight: CGFloat = 24
    static let presetHeight: CGFloat = 42 // 2372:8906
    static let presetRowHeight: CGFloat = 38 // 2372:8840
    static let presetListPadding: CGFloat = 2 // 2372:8838: 2 pt padding and gap
    static let settingsSectionPadding: CGFloat = 10 // 845:1597
    static let settingsBottomPadding: CGFloat = 20 // 767:2196
    static let wideRowHeight: CGFloat = 68 // 498:3009
    static let speedSectionBottomPadding: CGFloat = 15 // 5187:24539
    static let flipLabelHeight: CGFloat = 48 // 498:2984
    static let segmentHeight: CGFloat = 40 // I6114:13499;999:4559, inner selector height
    static let sizeModeSize = CGSize(width: 180, height: 38) // 804:1229
    static let sizeModeRowHeight: CGFloat = 50 // 800:1136
    static let cardTitleHeight: CGFloat = 37 // 498:3034, 536:1203, 536:1363
    static let expandHeaderHeight: CGFloat = 48 // 536:1512, 536:1521: Expand / Collapse Settings
    static let compactColorFieldWidth: CGFloat = 116 // 800:1147
    static let compactColorTrailingInset: CGFloat = 32 // 800:1147: 22 pt swatch, 5 pt inset, 5 pt gap
    static let cropFieldHeight: CGFloat = 33 // 774:1024
    static let cropLabelWidth: CGFloat = 60 // 774:1025/1026: the value starts 72 pt into the field
    static let cropLinkSize = CGSize(width: 30, height: 32) // 774:1081
    static let gradientSectionGap: CGFloat = 15 // 673:1662
    static let stereoTestSize = CGSize(width: 68, height: 32) // 536:1187
    static let stereoRowHeight: CGFloat = 52 // 1052:2921
    static let audioDelayTrackHeight: CGFloat = 21 // 1905:7353
    static let bookmarksHeaderHeight: CGFloat = 64 // 6320:13801
    static let chapterNumberWidth: CGFloat = 34 // 6321:14070
    /// Below this panel height the preset footer would leave no room for settings (P17).
    static let footerMinimumContentHeight: CGFloat = 104 // two 52 pt toggle rows
    /// Disabled and unavailable controls use the settings window's dimming (3062:10945 rows).
    static var disabledOpacity: Double { Theme.Metric.SettingsDetail.disabledRowOpacity }
}

struct PanelSurface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .foregroundStyle(Theme.Color.fgA2)
            .mxrTextStyle(Theme.Font.body)
            .background {
                // S14–S20/S22–S24 outer nodes specify BACKGROUND_BLUR 50. AppKit chooses
                // the physical within-window blur; retain the exact Figma tint and clipping.
                MXRBackdropSurface(tint: Theme.Color.bgB1Transparent,
                                   cornerRadius: Theme.Metric.SidePanels.settingsSidebar.radius ?? Theme.Radius.lg)
            }
            .clipShape(.rect(cornerRadius: Theme.Metric.SidePanels.settingsSidebar.radius ?? Theme.Radius.lg))
    }
}

// MARK: - Hover and pressed feedback (P12)

/// Hover and pressed states from Figma: Icon Wrapper 177:99 (FFFFFF 6 %), option 2107:5936
/// (BG/A2 row), Button 500:3064 (BG/A4 footer with an FG/A2 label).
struct PanelButtonStyle: ButtonStyle {
    enum Kind {
        /// Icon buttons in panel headers.
        case icon
        /// Full-width list rows (tracks, chapters, presets).
        case row
        /// The full-width footer button ("Show Preferences").
        case footer
        /// Text-only rows without a fill ("Open Advanced Settings").
        case link
    }
    var kind: Kind
    /// Disabled controls dim, except the queue header icons that already use FG/A3.
    var dimsWhenDisabled = true

    func makeBody(configuration: Configuration) -> some View {
        PanelButtonBody(configuration: configuration, kind: kind, dimsWhenDisabled: dimsWhenDisabled)
    }
}

private struct PanelButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PanelButtonStyle.Kind
    let dimsWhenDisabled: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let highlighted = isEnabled && (hovered || configuration.isPressed)
        configuration.label
            .foregroundStyle(labelStyle(highlighted))
            .background { background(highlighted) }
            .contentShape(Rectangle())
            .opacity(isEnabled || !dimsWhenDisabled ? 1 : PanelMetric.disabledOpacity)
            .onHover { hovered = $0 }
    }

    private func labelStyle(_ highlighted: Bool) -> ThemeColor {
        switch kind {
        case .footer, .link: highlighted ? Theme.Color.fgA2 : Theme.Color.fgA3
        case .icon, .row: Theme.Color.fgA2
        }
    }

    @ViewBuilder private func background(_ highlighted: Bool) -> some View {
        switch kind {
        case .icon:
            RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.iconHover.opacity(highlighted ? 1 : 0))
        case .row:
            RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgA2.opacity(highlighted ? 1 : 0))
        case .footer:
            RoundedRectangle(cornerRadius: Theme.Metric.SidePanels.footerButton.radius ?? Theme.Radius.md)
                .fill(highlighted ? Theme.Color.bgA4 : Theme.Color.bgB2)
        case .link:
            Color.clear
        }
    }
}

/// Hover and selection fill for rows that are not Buttons (queue and bookmark rows), the same
/// BG/A2 fill as `PanelButtonStyle(kind: .row)`.
private struct PanelRowFill: ViewModifier {
    let selected: Bool
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(Theme.Color.bgA2.opacity(selected || hovered ? 1 : 0), in: .rect(cornerRadius: Theme.Radius.md))
            .onHover { hovered = $0 }
    }
}

extension View {
    func panelRowFill(selected: Bool = false) -> some View { modifier(PanelRowFill(selected: selected)) }
}

// MARK: - Tabs

struct PanelTabStrip<Tab: Hashable>: View {
    let tabs: [Tab]
    let selected: Tab
    let title: (Tab) -> String
    let icon: (Tab) -> MXRIcon.Name
    let width: (Tab) -> CGFloat
    let select: (Tab) -> Void
    @State private var hoveredTab: Tab?
    @FocusState private var focusedTab: Tab?

    private func isNarrow(_ tab: Tab) -> Bool {
        tabs.count == 4 && width(tab) == Theme.Metric.SidePanels.tabCell4narrow.width
    }
    /// The icon and title's inset: 12 pt in a narrow four-tab cell (5187:24315), 8 pt otherwise.
    private func contentInset(_ tab: Tab) -> CGFloat {
        isNarrow(tab) ? Theme.Metric.SidePanels.tabCell4narrow.padding.leading : Theme.Metric.SidePanels.tabCell3.padding.leading
    }
    /// The underline's inset (inside the cell's width, before scaling to the strip).
    func underlineInset(_ tab: Tab) -> CGFloat {
        isNarrow(tab) && tab == selected ? PanelMetric.selectedNarrowTabUnderlineInset : contentInset(tab)
    }

    var body: some View {
        let strip = Theme.Metric.SidePanels.tabStrip
        GeometryReader { geometry in
            let totalCells = tabs.reduce(CGFloat.zero) { $0 + width($1) }
            let availableCells = max(0, geometry.size.width - strip.padding.leading * 2 - strip.gap * CGFloat(tabs.count - 1))
            let scale = availableCells / totalCells
            HStack(spacing: strip.gap) {
            ForEach(tabs, id: \.self) { tab in
                Button { select(tab) } label: {
                    VStack(spacing: Theme.Metric.SidePanels.tabCell3.gap) {
                        HStack(spacing: PanelSpace.sm) {
                            tabIcon(for: tab)
                            if geometry.size.width >= PanelMetric.tabTitlesMinimumWidth {
                                Text(title(tab)).mxrTextStyle(Theme.Font.caption)
                                .foregroundStyle(selected == tab || hoveredTab == tab ? Theme.Color.fgA2 : Theme.Color.fgA3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, contentInset(tab))
                        Rectangle().fill(selected == tab ? Theme.Color.accentMain : Theme.Color.bgB2)
                            .frame(height: Theme.Metric.SidePanels.tabUnderlineH)
                            .padding(.horizontal, underlineInset(tab))
                    }
                    .padding(.top, Theme.Metric.SidePanels.tabCell3.padding.top)
                    .frame(width: width(tab) * scale, height: strip.height, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hoveredTab = $0 ? tab : (hoveredTab == tab ? nil : hoveredTab) }
                .help(title(tab))
                .focused($focusedTab, equals: tab)
                .accessibilityAddTraits(selected == tab ? .isSelected : [])
                .accessibilityLabel(title(tab))
            }
        }
        .padding(.horizontal, strip.padding.leading)
        }
        .frame(height: strip.height)
        .background(Theme.Color.bgB2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
        .accessibilityRepresentation {
            Picker("Tabs", selection: Binding(get: { selected }, set: { select($0) })) {
                ForEach(tabs, id: \.self) { tab in Text(title(tab)).tag(tab) }
            }.pickerStyle(.segmented)
        }
        .onMoveCommand { direction in
            guard let index = tabs.firstIndex(of: selected) else { return }
            let target = direction == .left ? index - 1 : direction == .right ? index + 1 : index
            if tabs.indices.contains(target) { select(tabs[target]); focusedTab = tabs[target] }
        }
    }

    @ViewBuilder private func tabIcon(for tab: Tab) -> some View {
        let hovered = hoveredTab == tab && selected != tab
        if icon(tab) == .playback {
            if selected == tab {
                // 5187:24312 uses 6073:13944: accent inner triangle and gray outer outline.
                MXRIcon(.playback, tone: .twoTone, state: .selected, size: PanelMetric.tabIconSize)
            } else {
                // The same 6073:13944 artwork is flattened to FG/A4 in inactive sidebar tabs
                // (for example I2127:7749;6073:13946/13947), rather than the global mono variant.
                Rectangle().fill(hovered ? Theme.Color.fgA3 : Theme.Color.fgA4).frame(width: PanelMetric.tabIconSize, height: PanelMetric.tabIconSize)
                    .mask { MXRIcon(.playback, tone: .twoTone, state: .selected, size: PanelMetric.tabIconSize) }
                    .accessibilityHidden(true)
            }
        } else if icon(tab) == .queue && selected == tab {
            // I2127:7555;2461:9716/9717 override the queue list strokes to FG/A3.
            MXRIcon(.queue, tone: .twoTone, size: PanelMetric.tabIconSize, tint: Theme.Color.fgA3)
        } else {
            MXRIcon(icon(tab), tone: selected == tab ? .twoTone : .mono, size: PanelMetric.tabIconSize,
                    tint: selected == tab ? Theme.Color.fgA2 : (hovered ? Theme.Color.fgA3 : Theme.Color.fgA4))
        }
    }
}

// MARK: - Buttons and rows

struct PanelIconButton: View {
    let icon: MXRIcon.Name
    let label: String
    var active = false
    var width = Theme.Metric.ControlBar.prevNextCell.width
    var tint: ThemeColor = Theme.Color.fgA2
    var preservesDisabledTint = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            MXRIcon(icon, state: active ? .active : .default, tint: tint)
                .frame(width: width, height: Theme.Metric.ControlBar.prevNextCell.height)
        }
        // Queue source icons already use the muted FG/A3 tint, so they keep it when disabled.
        .buttonStyle(PanelButtonStyle(kind: .icon, dimsWhenDisabled: !preservesDisabledTint))
        .help(label).accessibilityLabel(label)
    }
}

struct PanelDivider: View {
    var consumesHeight = true
    var body: some View {
        Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.hairline)
            .frame(height: consumesHeight ? Theme.Stroke.hairline : 0)
    }
}

struct PanelToggle: View {
    let title: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: PanelMetric.toggleInset) {
                if isOn { Text("ON").frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.Color.bgAccentDark, in: .rect(cornerRadius: Theme.Radius.md)) }
                RoundedRectangle(cornerRadius: Theme.Radius.xs)
                    .fill(isOn ? Theme.Color.accentMain : Theme.Color.fgA4)
                    .frame(width: PanelMetric.toggleKnobWidth)
                if !isOn { Text("OFF").frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.Color.bgA4, in: .rect(cornerRadius: Theme.Radius.md)) }
            }
            .mxrTextStyle(Theme.Font.caption)
            .foregroundStyle(isOn ? Theme.Color.accentMain : Theme.Color.fgA3)
            .padding(PanelMetric.toggleInset)
            .frame(width: PanelMetric.toggleSize.width, height: PanelMetric.toggleSize.height)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.Color.bgB2, lineWidth: PanelMetric.controlBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : PanelMetric.disabledOpacity)
        .accessibilityLabel(title).accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A row label that explains, with an ⓘ tooltip, why its control is unavailable (D014).
struct PanelRowLabel: View {
    let title: String
    var unavailableReason: String?
    var body: some View {
        HStack(spacing: PanelSpace.sm) {
            Text(title).foregroundStyle(Theme.Color.fgA3).lineLimit(1)
            if let unavailableReason {
                MXRIcon(.info, size: Theme.Metric.SettingsDetail.infoSize, tint: Theme.Color.fgA4)
                    .help(unavailableReason)
                    .accessibilityHidden(true)
            }
        }
        .help(unavailableReason ?? "")
    }
}

struct PanelToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var height = PanelMetric.settingsRowHeight
    /// When set, the toggle is disabled and the label carries an ⓘ explaining why.
    var unavailableReason: String?
    var body: some View {
        HStack {
            PanelRowLabel(title: title, unavailableReason: unavailableReason)
            Spacer(minLength: PanelSpace.xs)
            PanelToggle(title: title, isOn: $isOn)
                .disabled(unavailableReason != nil)
                .accessibilityHint(unavailableReason ?? "")
        }
        .padding(.leading, PanelSpace.xs)
        .frame(height: height)
    }
}

/// Field chrome: the bordered settings input (4046:12353) or the borderless filled value
/// box used by the Playback speed row (5187:24542, no stroke, FG/A3 text, 12 pt inset).
enum PanelFieldStyle {
    case bordered
    case filled
}

struct PanelTextField: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    let trailingInset: CGFloat
    let style: PanelFieldStyle
    let width: CGFloat
    let font: Theme.TextStyle
    @State private var draft = ""
    @FocusState private var focused: Bool
    init(title: String, value: String, trailingInset: CGFloat = PanelSpace.md, style: PanelFieldStyle = .bordered,
         width: CGFloat = PanelMetric.fieldSize.width, font: Theme.TextStyle = Theme.Font.body,
         commit: @escaping (String) -> Void) {
        self.title = title; self.value = value; self.commit = commit
        self.trailingInset = trailingInset
        self.style = style
        self.width = width
        self.font = font
        _draft = State(initialValue: value)
    }
    var body: some View {
        TextField(title, text: $draft)
            .textFieldStyle(.plain)
            .mxrTextStyle(font)
            .foregroundStyle(style == .filled && !focused ? Theme.Color.fgA3 : Theme.Color.fgA2)
            // 6114:13535/4046:12354: bordered text starts 14 pt inside; 5187:24542 starts 12 pt inside.
            .padding(.leading, style == .bordered ? PanelSpace.md + PanelMetric.controlBorder : PanelSpace.md)
            .padding(.trailing, trailingInset)
            .frame(width: width, height: style == .bordered ? PanelMetric.fieldSize.height : PanelMetric.compactFieldHeight)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
            .overlay {
                if style == .bordered {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.bgA4, lineWidth: PanelMetric.controlBorder) // 6114:13534, 4046:12353: stroke style 217:222.
                }
            }
            .focused($focused)
            .onAppear { draft = value }
            .onChange(of: value) { _, new in if !focused { draft = new } }
            .onSubmit { commit(draft); draft = value }
            .onChange(of: focused) { old, new in if old && !new { commit(draft); draft = value } }
            .onExitCommand { draft = value; focused = false }
            .accessibilityLabel(title)
    }
}

struct PanelFieldRow: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    var height = PanelMetric.settingsRowHeight
    var style: PanelFieldStyle = .bordered
    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.Color.fgA3)
            Spacer(minLength: PanelSpace.xs)
            PanelTextField(title: title, value: value, style: style, commit: commit)
        }.padding(.leading, PanelSpace.xs).frame(height: height)
    }
}

// MARK: - Color

/// A hex field with a 22 pt swatch (4046:12374/12377). One click on the swatch opens the
/// system color panel directly (M3); the field stays the typed input.
struct PanelColorField: View {
    let title: String
    @Binding var color: MXRCore.RGBColor
    @State private var link = PanelColorPanelLink()
    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.Color.fgA3)
            Spacer(minLength: PanelSpace.xs)
            PanelTextField(title: title, value: color.hex, trailingInset: PanelMetric.colorFieldTrailingInset) { text in
                if let value = MXRCore.RGBColor(hex: text) { color = value }
            }.overlay(alignment: .trailing) {
                Button { link.open(color: color, title: title) { color = $0 } } label: {
                    RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(color.swiftUIColor)
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Color.swatchOutline, lineWidth: Theme.Stroke.icon))
                        .frame(width: PanelMetric.colorSwatchSize, height: PanelMetric.colorSwatchSize)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.trailing, Theme.Spacing.gap6 + Theme.Spacing.gap1)
                    .help("Choose \(title.lowercased())")
                    .accessibilityLabel("Choose \(title.lowercased())")
            }
        }
        .padding(.leading, PanelSpace.xs).frame(height: PanelMetric.settingsRowHeight)
        .onDisappear { link.detach() }
    }
}

/// Routes the shared NSColorPanel to the swatch that opened it, and only while it lives.
@MainActor
final class PanelColorPanelLink: NSObject {
    /// NSColorPanel does not retain or expose its target; remember which link owns it.
    private static weak var current: PanelColorPanelLink?
    private var apply: ((MXRCore.RGBColor) -> Void)?

    func open(color: MXRCore.RGBColor, title: String, apply: @escaping (MXRCore.RGBColor) -> Void) {
        self.apply = apply
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.setTarget(nil)
        panel.color = NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                              blue: CGFloat(color.blue) / 255, alpha: 1)
        panel.title = title
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        Self.current = self
        panel.orderFront(nil)
    }

    func detach() {
        apply = nil
        guard Self.current === self else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        Self.current = nil
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        func byte(_ component: CGFloat) -> UInt8 { UInt8((min(max(component, 0), 1) * 255).rounded()) }
        apply?(MXRCore.RGBColor(red: byte(rgb.redComponent), green: byte(rgb.greenComponent), blue: byte(rgb.blueComponent)))
    }
}

extension MXRCore.RGBColor {
    var swiftUIColor: Color {
        Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

// MARK: - Dropdowns

struct PanelChoice: Identifiable {
    let id: String
    let title: String
    var icon: MXRIcon.Name?
    let action: () -> Void
}

struct PanelDropdown: View {
    let title: String
    let selected: String
    let choices: [PanelChoice]
    var height = PanelMetric.dropdownSize.height
    var isPreset = false
    var leadingInset: CGFloat?
    var trailingInset: CGFloat?
    /// 673:1672: the Colors card's gradient mode reads FG/A3 while its filter is off; the chevron
    /// stays FG/A2.
    var valueColor = Theme.Color.fgA2
    /// The 2 pt frame: BG/B2, or BG/B1 for the Colors card's gradient mode (673:1670).
    var frameColor = Theme.Color.bgB2
    @State private var showingChoices = false
    var body: some View {
        Button { showingChoices.toggle() } label: {
            HStack {
                Text(selected).lineLimit(1).foregroundStyle(valueColor)
                Spacer(minLength: PanelSpace.xs)
                MXRIcon(isPreset ? .chevronUp : .chevronDown)
            }
            .mxrTextStyle(Theme.Font.body)
            .foregroundStyle(Theme.Color.fgA2)
            // 6114:13510/12/13: field content is inset 18 pt left and 14 pt right.
            // 2372:8906: the preset's nested option retains symmetric 16 pt insets.
            .padding(.leading, leadingInset ?? (isPreset ? PanelSpace.lg : PanelSpace.lg + PanelMetric.controlBorder))
            .padding(.trailing, trailingInset ?? (isPreset ? PanelSpace.lg : PanelSpace.md + PanelMetric.controlBorder))
            .frame(height: height)
            .background(isPreset ? Theme.Color.bgB2 : Theme.Color.bgA4, in: .rect(cornerRadius: Theme.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(frameColor, lineWidth: PanelMetric.controlBorder))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .mxrDropdownList(isPresented: $showingChoices, selectedRow: choices.firstIndex { $0.title == selected } ?? 0,
                         style: isPreset ? .preset : .standard, fieldInset: PanelMetric.controlBorder) {
            choices.map { choice in
                MXRMenuItem(choice.title, icon: choice.icon, isChecked: choice.title == selected) { choice.action() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel(title).accessibilityValue(selected)
    }
}

struct PanelDropdownRow: View {
    let title: String
    let selected: String
    let choices: [PanelChoice]
    var height = PanelMetric.wideRowHeight
    var body: some View {
        GeometryReader { geometry in
            HStack {
            Text(title).foregroundStyle(Theme.Color.fgA3)
            Spacer(minLength: PanelSpace.xs)
            PanelDropdown(title: title, selected: selected, choices: choices)
                .frame(width: max(PanelMetric.dropdownMinimumWidth,
                                  min(PanelMetric.dropdownSize.width, geometry.size.width - PanelMetric.dropdownLabelReserve)))
        }.padding(.leading, PanelSpace.xs).frame(height: height)
        }.frame(height: height)
    }
}

struct PanelSectionTitle: View {
    let title: String
    var body: some View {
        Text(title).mxrTextStyle(Theme.Font.sectionHeader).foregroundStyle(Theme.Color.fgA1)
            .offset(y: -1) // 845:1678: compensate AppKit's rounded ascent for the Figma baseline.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PanelSpace.xl + PanelSpace.xs)
            .padding(.top, PanelSpace.xl)
            .frame(height: PanelMetric.sectionTitleHeight, alignment: .top)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Slider

/// Settings slider (1905:7363). `labels` are evenly spaced over the range and centred under the
/// handle position of their value, clamped to the track (5187:24558, 1905:7369).
/// `ticks` adds the 5187:24548 marks at every inner label position; `stops` instead marks the inner
/// positions of that many evenly spaced stops. Figma draws no marks at the track ends (536:1860,
/// 614:1435, 612:1228, 804:1341): the end stops sit under the track's rounded caps.
struct PanelSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var center: Double?
    var labels: [String] = []
    var step: Double = 0.01
    var trackHeight = PanelMetric.sliderTrackHeight
    var ticks = false
    var stops: Int?
    /// 5187:24544 (Speed) nests the thumb's 24 pt frame and puts the labels 10 pt below it; the
    /// 1905:7365 slider (delays) measures the 10 pt from the track instead.
    var labelsBelowThumb = false
    /// VoiceOver value; defaults to the number.
    var valueDescription: String?
    /// The track sits centred in a frame `thumbOverhang` taller (the 24 pt thumb over the 16 pt track).
    private static let thumbOverhang = Theme.Spacing.gap8
    /// 614:1472/673:1606 (Colors, Color Threshold off): a disabled slider keeps its label and track
    /// but draws the fill in BG/A1 and the thumb in FG/A3.
    @Environment(\.isEnabled) private var isEnabled
    var tickFractions: [Double] {
        if let stops { return stops > 2 ? (1..<(stops - 1)).map { Double($0) / Double(stops - 1) } : [] }
        guard ticks, labels.count > 2 else { return [] }
        return (1..<(labels.count - 1)).map { Double($0) / Double(labels.count - 1) }
    }
    var body: some View {
        // 1905:7365: labels start 10 pt below the track, not below the thumb's frame, and the
        // wrapper keeps the thumb's 4 pt overhang beneath them.
        VStack(spacing: PanelMetric.sliderLabelsGap - (labelsBelowThumb ? 0 : Self.thumbOverhang / 2)) {
            GeometryReader { geometry in
                let layout = PanelSliderGeometry(width: geometry.size.width, snapsToTicks: stops != nil || !tickFractions.isEmpty)
                let progress = fraction(of: value)
                let fill = layout.fill(progress: progress, anchor: center.map(fraction(of:)))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgB2).frame(height: trackHeight)
                    RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(isEnabled ? Theme.Color.bgAccentBright : Theme.Color.bgA1)
                        .frame(width: fill.width, height: PanelMetric.sliderTrackHeight - PanelMetric.sliderInset * 2)
                        .offset(x: fill.minX)
                    // 536:1986 / 804:1287: the `degrees` frame screen-blends its BG/Accent Dark marks,
                    // so a tick reads lighter on the empty track and warmer on the fill.
                    ForEach(tickFractions, id: \.self) { tick in
                        Capsule().fill(Theme.Color.bgAccentDark)
                            .frame(width: PanelMetric.sliderTickSize.width, height: PanelMetric.sliderTickSize.height)
                            .offset(x: layout.tickCenter(tick) - PanelMetric.sliderTickSize.width / 2)
                    }.blendMode(.screen)
                    RoundedRectangle(cornerRadius: Theme.Radius.md).fill(isEnabled ? Theme.Color.accentDim : Theme.Color.fgA3)
                        .frame(width: PanelMetric.sliderHandleSize.width, height: PanelMetric.sliderHandleSize.height)
                        .offset(x: layout.thumbX(progress))
                }
                .frame(height: trackHeight + Self.thumbOverhang)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                    let next = range.lowerBound + layout.fraction(atX: gesture.location.x) * (range.upperBound - range.lowerBound)
                    value = min(max((next / step).rounded() * step, range.lowerBound), range.upperBound)
                })
            }.frame(height: trackHeight + Self.thumbOverhang)
            if !labels.isEmpty {
                // 1905:7369 (delays) spreads its labels flush with the track ends; 5187:24558 (Speed)
                // keeps the end labels 2 pt inside, like the thumb.
                PanelSliderLabelsLayout(handleWidth: PanelMetric.sliderHandleSize.width,
                                        edgeInset: labelsBelowThumb ? PanelMetric.sliderInset : 0) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in Text(label) }
                }.mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                    .padding(.bottom, labelsBelowThumb ? 0 : Self.thumbOverhang / 2)
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(valueDescription ?? String(format: "%.2f", value))
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }
    private func fraction(of value: Double) -> Double {
        min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }
}

/// Where a panel slider draws its parts along a track `width` pt wide, as Figma's sliders do
/// (1905:7366, 804:1285, 536:1986, 607:1124): the thumb travels 2 pt inside both track ends (804:1177
/// at the minimum, 607:1155 at the maximum, 1905:7355 centred at 176 of 360); ticks are spread over
/// the track's inner 2…W−2 span (the `degrees` frames 2.2…357.8 and 2…326), and a ticked slider's
/// thumb is centred on the tick of its value (804:1299, 804:1315, 607:1136, 536:1919, 673:1702),
/// held inside the travel at the ends (848:1698). The fill runs from the track's 2 pt inset to the
/// thumb's far edge; a centred slider's fill spans the thumb at the value and the thumb at the zero
/// point (1905:7367: 107…184 for −4 s of ±10 s).
struct PanelSliderGeometry: Equatable {
    let width: CGFloat
    var snapsToTicks = false
    private var inset: CGFloat { PanelMetric.sliderInset }
    private var handle: CGFloat { PanelMetric.sliderHandleSize.width }
    private var travel: CGFloat { max(1, width - handle - 2 * inset) }
    private var tickSpan: CGFloat { max(1, width - 2 * inset) }
    /// The thumb's leading edge at `fraction` of the range.
    func thumbX(_ fraction: Double) -> CGFloat {
        guard snapsToTicks else { return inset + CGFloat(fraction) * travel }
        return min(max(tickCenter(fraction) - handle / 2, inset), inset + travel)
    }
    /// The fill's horizontal span; `anchor` is the zero point's fraction of a centred slider.
    func fill(progress: Double, anchor: Double?) -> (minX: CGFloat, width: CGFloat) {
        guard let anchor else { return (inset, max(0, thumbX(progress) + handle - inset)) }
        let start = thumbX(min(progress, anchor)), end = thumbX(max(progress, anchor)) + handle
        return (start, end - start)
    }
    /// A tick's centre at `fraction`.
    func tickCenter(_ fraction: Double) -> CGFloat { inset + CGFloat(fraction) * tickSpan }
    /// The range fraction a pointer at `x` puts the thumb's centre on.
    func fraction(atX x: CGFloat) -> Double {
        let fraction = snapsToTicks ? (x - inset) / tickSpan : (x - inset - handle / 2) / travel
        return Double(min(max(fraction, 0), 1))
    }
}

/// A setting whose value is plain text above a stepped, ticked slider (804:1341 Font Size,
/// 804:1342 Outline Thickness, 848:1686 Background Opacity): 10 pt padding, the 37 pt text row,
/// a 5 pt gap and the 24 pt slider (86 pt in all).
struct PanelValueSliderRow: View {
    let title: String
    let value: String
    @Binding var position: Double
    let range: ClosedRange<Double>
    let step: Double
    var body: some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            HStack {
                Text(title)
                Spacer(minLength: PanelSpace.xs)
                Text(value)
            }
            .foregroundStyle(Theme.Color.fgA3).lineLimit(1)
            .padding(.horizontal, PanelSpace.xs).frame(height: PanelMetric.valueTextRowHeight)
            .accessibilityHidden(true)
            PanelSlider(title: title, value: $position, range: range, step: step,
                        stops: Int(((range.upperBound - range.lowerBound) / step).rounded()) + 1, valueDescription: value)
        }
        .padding(.vertical, Theme.Spacing.gap10)
    }
}

/// Places evenly spaced labels centred on the handle positions, clamped to the track.
private struct PanelSliderLabelsLayout: Layout {
    let handleWidth: CGFloat
    let edgeInset: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(width: proposal.width ?? sizes.reduce(0) { $0 + $1.width },
                      height: sizes.map(\.height).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let travel = max(0, bounds.width - handleWidth)
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let fraction = subviews.count > 1 ? Double(index) / Double(subviews.count - 1) : 0.5
            let center = bounds.minX + handleWidth / 2 + fraction * travel
            let x = min(max(center - size.width / 2, bounds.minX + edgeInset), bounds.maxX - edgeInset - size.width)
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
        }
    }
}

// MARK: - Expand

/// A filter card's settings (§07). Closed: the BG/B2 "Expand Settings ›" bar (536:1512).
/// Open: one BG/A3 card holding the "Collapse Settings ⌄" header and the rows (536:1514, 536:1860,
/// 543:995, 614:1435, 6114:13615, 08m49.0). The header is 48 pt with 16/10 pt insets; the card has
/// a 10 pt bottom padding. Rows span the whole card and set their own 16 pt insets, so a section
/// divider can run edge to edge (614:1435).
struct PanelExpand<Content: View>: View {
    let title: String
    let content: Content
    @State private var expanded: Bool
    init(title: String, expanded: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        _expanded = State(initialValue: expanded)
    }
    var body: some View {
        VStack(spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(expanded ? "Collapse Settings" : "Expand Settings")
                    Spacer(minLength: PanelSpace.xs)
                    // 536:1516 / 536:1507: the chevron takes the label's FG/A3 (FG/A2 on hover).
                    MXRIcon(expanded ? .chevronDown : .chevronRight, tint: nil)
                }
                .padding(.leading, PanelSpace.lg).padding(.trailing, Theme.Spacing.gap10)
                .frame(height: PanelMetric.expandHeaderHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PanelButtonStyle(kind: .link))
            .accessibilityLabel("\(title): \(expanded ? "Collapse" : "Expand") settings")
            if expanded {
                VStack(spacing: 0) { content }.frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, expanded ? Theme.Spacing.gap10 : 0)
        .background(expanded ? Theme.Color.bgA3 : Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
    }
}

/// A slider row inside an open filter card (536:1541, 536:1864): the label, and the value as plain
/// text when the frame shows one (Compressor, Spatializer, Stereo Widener), over the slider; 16 pt
/// insets, a 37 pt text row, 5 pt gap, the 24 pt slider and 10 pt below (76 pt).
struct PanelCardSliderRow: View {
    let title: String
    var value: String?
    @Binding var number: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01
    var stops: Int?
    var bottomPadding = Theme.Spacing.gap10
    var body: some View {
        VStack(spacing: PanelMetric.settingsRowGap) {
            HStack {
                Text(title)
                Spacer(minLength: PanelSpace.xs)
                if let value { Text(value) }
            }
            .foregroundStyle(Theme.Color.fgA3).lineLimit(1)
            .frame(height: PanelMetric.valueTextRowHeight)
            .accessibilityHidden(true)
            PanelSlider(title: title, value: $number, range: range, step: step, stops: stops, valueDescription: value)
        }
        .padding(.horizontal, PanelSpace.lg).padding(.bottom, bottomPadding)
    }
}

/// An equalizer band inside the open card (6114:13619): the label and a 140 × 36 value field in a
/// 56 pt row, the slider right below, 10 pt under it (90 pt).
struct PanelCardFieldSliderRow: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    @Binding var number: Double
    let range: ClosedRange<Double>
    var center: Double?
    var step: Double = 0.01
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).foregroundStyle(Theme.Color.fgA3)
                Spacer(minLength: PanelSpace.xs)
                // 6114:13826: the equalizer's values are 12 pt.
                PanelTextField(title: title, value: value, font: Theme.Font.caption, commit: commit)
            }
            .frame(height: PanelMetric.fieldRowHeight)
            PanelSlider(title: title, value: $number, range: range, center: center, step: step, valueDescription: value)
        }
        .padding(.horizontal, PanelSpace.lg).padding(.bottom, Theme.Spacing.gap10)
    }
}

/// A label with trailing controls inside an open card (614:1567, 673:1621, 673:1638): 16 pt insets,
/// the 32 pt controls 8 pt apart; the caller sets the vertical padding of its section.
struct PanelCardToggleRow<Accessory: View>: View {
    let title: String
    @Binding var isOn: Bool
    let accessory: Accessory
    init(title: String, isOn: Binding<Bool>, @ViewBuilder accessory: () -> Accessory = { EmptyView() }) {
        self.title = title
        _isOn = isOn
        self.accessory = accessory()
    }
    var body: some View {
        HStack(spacing: PanelSpace.sm) {
            Text(title).foregroundStyle(Theme.Color.fgA3).lineLimit(1)
            Spacer(minLength: PanelSpace.xs)
            accessory
            PanelToggle(title: title, isOn: $isOn)
        }
        .frame(height: PanelMetric.toggleSize.height)
    }
}

/// The compact color value of the Colors card (800:1147): a 116 × 32 BG/B2 box, the hex in FG/A3
/// 12 pt in, the 22 pt swatch 5 pt from the right edge; the swatch opens the system color panel.
struct PanelCompactColorField: View {
    let title: String
    @Binding var color: MXRCore.RGBColor
    @State private var link = PanelColorPanelLink()
    var body: some View {
        PanelTextField(title: title, value: color.hex, trailingInset: PanelMetric.compactColorTrailingInset,
                       style: .filled, width: PanelMetric.compactColorFieldWidth) { text in
            if let value = MXRCore.RGBColor(hex: text) { color = value }
        }
        .overlay(alignment: .trailing) {
            Button { link.open(color: color, title: title) { color = $0 } } label: {
                RoundedRectangle(cornerRadius: Theme.Radius.xs).fill(color.swiftUIColor)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Color.swatchOutline, lineWidth: Theme.Stroke.icon)) // 800:1149
                    .frame(width: PanelMetric.colorSwatchSize, height: PanelMetric.colorSwatchSize)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.trailing, Theme.Spacing.gap5)
                .help("Choose \(title.lowercased())")
                .accessibilityLabel("Choose \(title.lowercased())")
        }
        .onDisappear { link.detach() }
    }
}

func panelNumber(_ text: String) -> Double? {
    guard let value = Double(text.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""), value.isFinite else { return nil }
    return value
}
