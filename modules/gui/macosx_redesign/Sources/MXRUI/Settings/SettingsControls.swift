import AppKit
import MXRCore
import MXRDesign
import SwiftUI

enum SettingsValueEditing {
    static func number(_ text: String, row: SettingsRow, current: SettingValue?, isFloat: Bool = false) -> SettingValue? {
        guard let number = Double(text.trimmingCharacters(in: .whitespaces)), number.isFinite,
              number >= (row.min ?? -Double.greatestFiniteMagnitude),
              number <= (row.max ?? Double.greatestFiniteMagnitude) else { return nil }
        if isFloat { return .float(number) }
        if case .float = current { return .float(number) }
        guard number.rounded() == number, number >= Double(Int.min), number < Double(Int.max) else { return nil }
        return .integer(Int(number))
    }

    static func color(_ text: String) -> SettingValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, digits.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
              let value = Int(digits, radix: 16) else { return nil }
        return .integer(value)
    }

    static func slider(_ value: Double, current: SettingValue?, step: Double = 1, isFloat: Bool = false) -> SettingValue {
        if isFloat || step.rounded() != step { return .float(value) }
        if case .integer = current { return .integer(Int(value.rounded())) }
        return .float(value)
    }
}

struct SettingsButton: View {
    let title: String
    var primary = false
    var width: CGFloat? = Theme.Metric.buttonWidth
    var surface: ThemeColor = Theme.Color.bgA4
    /// The dialog fill a disabled primary button blends with (Keyboard Shortcuts 2437:14832).
    var backdrop: ThemeColor = Theme.Color.bgA3Transparent
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title).mxrTextStyle(Theme.Font.button)
                .foregroundStyle(primary && !isEnabled ? AnyShapeStyle(FigmaDisabledLuminosity(token: Theme.Color.accentMain, backdrop: backdrop))
                                 : primary ? AnyShapeStyle(MXRAccentLabel()) : AnyShapeStyle(Theme.Color.fgA2))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metric.buttonHeight)
                .background(primary && !isEnabled ? AnyShapeStyle(FigmaDisabledLuminosity(token: Theme.Color.bgAccentBright, backdrop: backdrop))
                            : AnyShapeStyle(primary ? Theme.Color.bgAccentBright : surface),
                            in: .rect(cornerRadius: Theme.Radius.lg))
        }
        .buttonStyle(.plain)
        .frame(width: width)
    }
}

/// Figma 2437:14853 blends its disabled primary button with Luminosity (at the 50 % opacity macOS
/// gives a disabled button). NSHostingView does not apply nonseparable blend modes consistently, so
/// the blend is resolved here, by the W3C compositing formula Figma uses, against the dialog fill
/// behind the button: Cs' = (1 − αb)·Cs + αb·SetLum(Cb, Lum(Cs)). Over the 95 % dialog fill a trace
/// of the button's own colour remains, which is what Figma draws (#1F1E1D, not a neutral grey).
struct FigmaDisabledLuminosity: ShapeStyle {
    let token: ThemeColor
    let backdrop: ThemeColor

    func resolve(in environment: EnvironmentValues) -> Color {
        let scheme = environment.colorScheme
        // Light dialogs use the opaque form of their fill (D045).
        let behind = scheme == .light ? backdrop.opaqueCounterpart : backdrop
        return Self.blend(token.value(scheme: scheme, accent: environment.mxrAccent),
                          over: behind.value(scheme: scheme, accent: environment.mxrAccent)).color
    }

    static func blend(_ source: Theme.RGBA, over backdrop: Theme.RGBA) -> Theme.RGBA {
        func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { r * 0.3 + g * 0.59 + b * 0.11 }
        // SetLum(Cb, Lum(Cs)) with ClipColor.
        let delta = lum(source.red, source.green, source.blue) - lum(backdrop.red, backdrop.green, backdrop.blue)
        var c = (backdrop.red + delta, backdrop.green + delta, backdrop.blue + delta)
        let l = lum(c.0, c.1, c.2), low = min(c.0, c.1, c.2), high = max(c.0, c.1, c.2)
        if low < 0 { c = (l + (c.0 - l) * l / (l - low), l + (c.1 - l) * l / (l - low), l + (c.2 - l) * l / (l - low)) }
        if high > 1 { c = (l + (c.0 - l) * (1 - l) / (high - l), l + (c.1 - l) * (1 - l) / (high - l), l + (c.2 - l) * (1 - l) / (high - l)) }
        let a = backdrop.alpha
        return Theme.RGBA(red: (1 - a) * source.red + a * c.0, green: (1 - a) * source.green + a * c.1,
                          blue: (1 - a) * source.blue + a * c.2)
    }
}

struct SettingsSearch: View {
    @Binding var text: String
    var placeholder = "Search"

    var body: some View {
        HStack(spacing: Theme.Spacing.gap10) {
            MXRIcon(.search, tint: Theme.Color.fgA3)
            // macOS ignores a prompt's color, so the placeholder is drawn in FG/A4 here (SD-27).
            TextField("", text: $text)
                .textFieldStyle(.plain).mxrTextStyle(Theme.Font.body)
                .foregroundStyle(Theme.Color.fgA1)
                .overlay(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA4)
                            .lineLimit(1).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .accessibilityLabel(placeholder)
            if !text.isEmpty {
                Button { text = "" } label: { MXRIcon(.close, size: Theme.Metric.SettingsDetail.infoSize) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.gap8)
        .frame(height: Theme.Metric.textFieldHeight)
        .background(Theme.Color.bgA5, in: .rect(cornerRadius: Theme.Radius.lg))
    }
}

struct SettingsToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Theme.Metric.SettingsDetail.toggleGap) {
                if isOn { labelCell }
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(isOn ? Theme.Color.accentDim : Theme.Color.fgA4)
                    .frame(width: Theme.Metric.Controls.toggleKnob.width,
                           height: Theme.Metric.Controls.toggleKnob.height)
                if !isOn { labelCell }
            }
            .padding(Theme.Metric.SettingsDetail.toggleInset)
            .frame(width: Theme.Metric.Controls.toggle.width, height: Theme.Metric.Controls.toggle.height, alignment: .leading)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        }
        // 6542:15562/6542:15575 dim the complete row to 30%; avoid a second native button dimming.
        .buttonStyle(SettingsToggleButtonStyle())
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var labelCell: some View {
        Text(isOn ? "ON" : "OFF").mxrTextStyle(Theme.Font.caption)
            .foregroundStyle(isOn ? AnyShapeStyle(MXRAccentLabel()) : AnyShapeStyle(MXRInactiveSegmentLabel()))
            .frame(width: Theme.Metric.Controls.toggleLabelCell.width,
                   height: Theme.Metric.Controls.toggleLabelCell.height)
            .background(isOn ? Theme.Color.bgAccentBright : Theme.Color.bgA4,
                        in: .rect(cornerRadius: Theme.Radius.sm))
    }
}

private struct SettingsToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

struct SettingsChoiceMenu: View {
    let title: String
    let choices: [SettingChoice]
    let selected: SettingValue?
    let select: (SettingChoice) -> Void
    var compact = false
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Theme.Spacing.gap10) {
                Text(title).mxrTextStyle(Theme.Font.body).lineLimit(1)
                Spacer(minLength: 0)
                MXRIcon(.chevronDown)
            }
            .foregroundStyle(Theme.Color.fgA2)
            .padding(.leading, compact ? Theme.Spacing.gap12 : Theme.Spacing.gap14)
            .padding(.trailing, compact ? Theme.Spacing.gap8 : Theme.Spacing.gap14)
            .frame(height: compact ? Theme.Metric.textFieldHeight : Theme.Metric.SettingsDetail.controlInnerHeight)
            .background(compact ? Theme.Color.bgA5 : Theme.Color.bgA4, in: .rect(cornerRadius: compact ? Theme.Radius.lg : Theme.Radius.md))
            .padding(compact ? 0 : Theme.Spacing.gap2)
            .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        }
        .buttonStyle(.plain)
        .mxrDropdownList(isPresented: $isOpen,
                         selectedRow: choices.firstIndex { selected?.isEquivalent(to: $0.value) ?? false } ?? 0,
                         fieldInset: compact ? 0 : Theme.Spacing.gap2) {
            choices.map { choice in
                MXRMenuItem(choice.title, isChecked: selected?.isEquivalent(to: choice.value) ?? false) { select(choice) }
            }
        }
    }
}

struct SettingsTextEditor: View {
    let row: SettingsRow
    @Environment(SettingsModel.self) private var settings
    @Environment(\.isEnabled) private var isEnabled
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        // A number's unit follows it at one space ("5000 ms", 6571:16412): the field's own cell
        // inset is that space, so no stack spacing is added.
        HStack(spacing: row.control == .number ? 0 : Theme.Spacing.gap8) {
            if settings.backend.option(named: row.option ?? "")?.type == .password {
                SecureField(row.placeholder ?? "", text: $text).textFieldStyle(.plain).focused($focused)
            } else if row.control == .number {
                // macOS ignores a prompt's color, so "Auto" is drawn in FG/A4 here (SD-27); the field
                // is as wide as its text or that placeholder, and a click anywhere on it edits.
                ZStack(alignment: .leading) {
                    if text.isEmpty, let placeholder = row.placeholder {
                        Text(placeholder).foregroundStyle(Theme.Color.fgA4).lineLimit(1).accessibilityHidden(true)
                    }
                    TextField("", text: $text).textFieldStyle(.plain).focused($focused)
                        .accessibilityLabel(row.label)
                        .accessibilityValue(text.isEmpty ? (row.placeholder ?? "") : text)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: Theme.Spacing.gap8, maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: true, vertical: false)
                .contentShape(.rect).onTapGesture { focused = true }
            } else {
                TextField(row.placeholder ?? "", text: $text).textFieldStyle(.plain).focused($focused)
            }
            if let unit = row.unit { Text(unit) }
            if row.control == .number { Spacer(minLength: 0) }
            if row.control == .color {
                RoundedRectangle(cornerRadius: Theme.Radius.xs)
                    .fill(Theme.RGBA(hex: UInt32(settings.value(for: row)?.intValue ?? 0)).color)
                    .frame(width: Theme.Metric.SettingsDetail.colorSwatchSize, height: Theme.Metric.SettingsDetail.colorSwatchSize)
                    .overlay { RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Color.swatchOutline, lineWidth: Theme.Metric.SettingsDetail.colorSwatchStroke) }
            }
        }
        .mxrTextStyle(Theme.Font.body)
        // 6543:15649 draws a disabled field empty; the value it would use (the Buffering preset's)
        // stays readable only as a placeholder.
        .foregroundStyle(isEnabled ? Theme.Color.fgA2 : Theme.Color.fgA4)
        // Figma's inset stroke contributes two points to the autolayout padding (3180:18103).
        .padding(.leading, row.control == .color ? Theme.Spacing.gap12 : Theme.Spacing.gap14)
        .padding(.trailing, row.control == .color ? Theme.Spacing.gap5 : Theme.Metric.SettingsDetail.inputTrailingPadding + Theme.Spacing.gap2)
        .frame(height: row.control == .color ? Theme.Metric.SettingsDetail.controlInnerHeight : Theme.Metric.SettingsDetail.controlHeight)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        .overlay {
            if invalid || row.control != .color {
                RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(invalid ? Theme.Color.accentMain : Theme.Color.bgA4, lineWidth: Theme.Spacing.gap2)
            }
        }
        .onSubmit(commit)
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: settings.revision) { _, _ in if !focused { reload() } }
        .onAppear(perform: reload)
        .onDisappear(perform: commit)
        .accessibilityLabel(row.label)
        .accessibilityHint(invalid ? "Enter a valid value within the allowed range." : row.info ?? "")
    }

    private func reload() {
        invalid = false
        if row.control == .color { text = String(format: "#%06X", settings.value(for: row)?.intValue ?? 0) }
        else if settings.backend.option(named: row.option ?? "")?.type == .float, settings.double(row).rounded() == settings.double(row) {
            text = String(format: "%.1f", settings.double(row))
        }
        else if case .float(let value) = settings.value(for: row), value.rounded() == value { text = String(format: "%.1f", value) }
        else { text = settings.string(row) }
    }

    private func commit() {
        guard SettingsAvailability.isAvailable(row, in: settings) else { return }
        let value: SettingValue?
        if row.automaticValue != nil, text.trimmingCharacters(in: .whitespaces).isEmpty {
            invalid = false
            if settings.value(for: row) != nil { settings.setAutomatic(for: row) }
            return
        }
        switch row.control {
        case .number: value = SettingsValueEditing.number(text, row: row, current: settings.value(for: row),
                                                        isFloat: settings.backend.option(named: row.option ?? "")?.type == .float)
        case .color: value = SettingsValueEditing.color(text)
        default: value = .string(text)
        }
        invalid = value == nil
        if let value, value != settings.value(for: row) { settings.setValue(value, for: row) }
    }
}

struct SettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// Figma's tick count for this slider, both ends included; nil derives it from ``step``.
    var ticks: Int? = nil
    var labels: [String] = []
    var compactScale = false
    var label: String
    @Environment(\.colorScheme) private var colorScheme

    /// The catalog's count, else one tick per step when that stays readable (3056:10875 "Hide after":
    /// 0.5 s steps), else tenths (SD-27).
    var tickPositions: Int {
        if let ticks, ticks >= 2 { return ticks }
        let steps = step > 0 ? ((range.upperBound - range.lowerBound) / step).rounded() : 0
        return steps >= 2 && steps <= 20 ? Int(steps) + 1 : 11
    }

    /// Where scale label `index` of `count` is drawn under a track `width` wide with `ticks` ticks:
    /// the tick at the same fraction of the scale (ticks run between the track's 2 pt insets and are
    /// 2 pt wide), centred. The end labels start and end there when every tick has a label
    /// (3062:13083, the speed scale), and at the track's edges when only some do (3176:16483).
    static func labelAnchor(index: Int, count: Int, width: CGFloat, ticks: Int) -> (x: CGFloat, alignment: Alignment) {
        let inset = Theme.Spacing.gap2, tick = Theme.Spacing.gap2
        guard count > 1 else { return (width / 2, .center) }
        let edge = count == ticks ? inset : 0
        if index == 0 { return (edge, .leading) }
        if index == count - 1 { return (width - edge, .trailing) }
        let fraction = CGFloat(index) / CGFloat(count - 1)
        return (inset + tick / 2 + fraction * (width - inset * 2 - tick), .center)
    }

    var body: some View {
        VStack(spacing: compactScale ? Theme.Spacing.gap8 : Theme.Spacing.gap10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let span = range.upperBound - range.lowerBound
                let fraction = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
                let positions = tickPositions
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgB2).frame(height: Theme.Spacing.gap16)
                    RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgAccentBright)
                        .frame(width: max(0, (width - Theme.Spacing.gap4) * fraction), height: Theme.Spacing.gap12)
                        .offset(x: Theme.Spacing.gap2)
                    // Figma's "degrees" group blends its BG/Accent Dark ticks with Screen, so they lighten
                    // both the accent fill and the empty track (3176:16473). Light has no Figma slider
                    // frame; there the light token is drawn as is (D032).
                    HStack(spacing: 0) {
                        ForEach(0..<positions, id: \.self) { index in
                            Rectangle().fill(Theme.Color.bgAccentDark).frame(width: Theme.Spacing.gap2, height: Theme.Spacing.gap6)
                                .opacity(index == 0 || index == positions - 1 ? 0 : 1)
                            if index < positions - 1 { Spacer(minLength: 0) }
                        }
                    }.padding(.horizontal, Theme.Spacing.gap2)
                    .blendMode(colorScheme == .dark ? .screen : .normal)
                    RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.accentDim)
                        .frame(width: Theme.Spacing.gap8, height: Theme.Metric.iconSize)
                        .offset(x: min(max(0, width * fraction - Theme.Spacing.gap4), width - Theme.Spacing.gap8))
                }
                // 3056:10875 keeps its 24-point thumb centered over a 16-point range.
                .frame(height: compactScale ? Theme.Spacing.gap16 : Theme.Metric.iconSize)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let raw = range.lowerBound + min(max(drag.location.x / width, 0), 1) * (range.upperBound - range.lowerBound)
                    value = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                })
            }.frame(height: compactScale ? Theme.Spacing.gap16 : Theme.Metric.iconSize)
            if !labels.isEmpty {
                // 3062:13083: each label stands under its tick, so "1" sits under the thumb at 1×.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        ForEach(Array(labels.enumerated()), id: \.offset) { i, text in
                            let anchor = Self.labelAnchor(index: i, count: labels.count, width: geometry.size.width, ticks: tickPositions)
                            Text(text).mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA3)
                                .lineLimit(1).fixedSize()
                                .frame(width: 0, alignment: anchor.alignment)
                                .offset(x: anchor.x)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                }
                .frame(height: Theme.Metric.SettingsDetail.sliderLabelHeight)
            }
        }
        .padding(.vertical, Theme.Spacing.gap4)
        .mxrKeyboardFocusable(cornerRadius: Theme.Radius.md) // no system focus ring on click (C1, D028)
        .onKeyPress(.leftArrow) { value = max(range.lowerBound, value - step); return .handled }
        .onKeyPress(.rightArrow) { value = min(range.upperBound, value + step); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value.formatted())
        .accessibilityAdjustableAction { direction in
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }
}

/// The inline value in the second stacked choice. Keep partial input local until commit.
struct SettingsSecondaryValueEditor: View {
    let row: SettingsRow
    let isSelected: Bool
    @Environment(SettingsModel.self) private var settings
    @Environment(\.settingsControlWidth) private var controlWidth
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        // 3176:16574 reads "200%": while not editing, the value and its unit are one text, because
        // a field's cell insets would put a gap before the unit.
        ZStack(alignment: .leading) {
            TextField("Volume", text: $text).textFieldStyle(.plain).focused($focused)
                .disabled(!isSelected)
                .opacity(focused ? 1 : 0)
            if !focused {
                Text(text + (row.unit ?? "")).lineLimit(1).accessibilityHidden(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                    .onTapGesture { if isSelected { focused = true } }
            }
        }
        .mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
        .opacity(isSelected ? 1 : 0.4) // I3176:16574;3176:16554 disabled value opacity.
        .padding(.leading, Theme.Spacing.gap12).padding(.trailing, Theme.Metric.SettingsDetail.inputTrailingPadding)
        .frame(width: controlWidth >= Theme.Metric.SettingsDetail.controlWidth ? Theme.Metric.SettingsDetail.secondaryInputWidth : controlWidth / 2,
               height: Theme.Metric.SettingsDetail.controlInnerHeight)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.xs))
        .overlay { if invalid { RoundedRectangle(cornerRadius: Theme.Radius.xs).strokeBorder(Theme.Color.accentMain) } }
        .onAppear { reload() }
        .onChange(of: settings.revision) { _, _ in if !focused { reload() } }
        .onSubmit(commit)
        .onChange(of: focused) { _, value in if !value { commit() } }
        .onDisappear(perform: commit)
        .accessibilityLabel("\(row.label) level")
        .accessibilityHint(invalid ? "Enter a volume from zero to 300 percent." : "")
    }

    private func reload() { invalid = false; text = settings.secondaryValue(for: row)?.description ?? "" }
    private func commit() {
        guard SettingsAvailability.isAvailable(row, in: settings) else { return }
        let input = SettingsRow(option: row.secondaryOption, control: .number, label: row.label, min: 0, max: 300)
        guard let value = SettingsValueEditing.number(text, row: input, current: settings.secondaryValue(for: row),
                                                     isFloat: settings.backend.option(named: row.secondaryOption ?? "")?.type == .float) else { invalid = true; return }
        invalid = false
        if value != settings.secondaryValue(for: row) { settings.setSecondaryValue(value, for: row) }
    }
}
