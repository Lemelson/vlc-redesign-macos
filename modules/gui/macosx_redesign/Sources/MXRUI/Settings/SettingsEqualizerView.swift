import MXRCore
import MXRDesign
import SwiftUI

struct SettingsEqualizerView: View {
    let row: SettingsRow
    let close: () -> Void
    @Environment(SettingsModel.self) private var settings

    private var bands: [Double] {
        let values = settings.string(row).split(separator: " ").compactMap { Double($0) }
        return Array((values + Array(repeating: 0, count: 10)).prefix(10))
    }
    private var preampRow: SettingsRow {
        SettingsRow(option: "equalizer-preamp", control: .slider, label: "Preamp", min: -20, max: 20, apply: row.apply)
    }

    var body: some View {
        VStack(spacing: Theme.Metric.Dialogs.equalizerPanel.gap) {
            Button(action: close) {
                HStack(spacing: Theme.Spacing.gap10) {
                    Text("Close Equalizer").mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA2)
                    MXRIcon(.chevronDown)
                }.frame(height: Theme.Metric.iconSize)
            }.buttonStyle(.plain)
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.gap8) {
                    band(label: "Preamp", binding: Binding(get: { settings.double(preampRow) }, set: { settings.setValue(.float($0), for: preampRow) }))
                    ForEach(0..<10) { index in
                        band(label: EqualizerSettings.bandLabels[index], binding: Binding(get: { bands[index] }, set: { gain in
                            var values = bands
                            values[index] = gain
                            settings.setValue(.string(values.map { String($0) }.joined(separator: " ")), for: row)
                        }))
                    }
                }.frame(minWidth: Theme.Metric.Dialogs.settingsContent.width - Theme.Metric.Dialogs.settingsContent.padding.leading
                           - Theme.Metric.Dialogs.settingsContent.padding.trailing)
            }
            .scrollIndicators(.hidden)
            .frame(height: Theme.Metric.SettingsDetail.equalizerTrackHeight + Theme.Metric.SettingsDetail.equalizerBandGap
                   + Theme.Metric.SettingsDetail.equalizerValueGroupHeight)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Metric.Dialogs.equalizerPanel.padding.edgeInsets)
        .background(Theme.Color.bgA4, in: .rect(cornerRadius: Theme.Metric.Dialogs.equalizerPanel.radius ?? Theme.Radius.xs))
    }

    private func band(label: String, binding: Binding<Double>) -> some View {
        VStack(spacing: Theme.Metric.SettingsDetail.equalizerBandGap) {
            GeometryReader { geometry in
                let h = geometry.size.height
                let fraction = (binding.wrappedValue + 20) / 40
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.Color.bgB2)
                    RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.bgAccentBright)
                        .frame(width: Theme.Spacing.gap12, height: (h - Theme.Spacing.gap4) * fraction)
                        .offset(y: -Theme.Spacing.gap2)
                    RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.Color.accentDim)
                        .frame(width: Theme.Metric.iconSize, height: Theme.Spacing.gap8)
                        .offset(y: -min(max(h * fraction - Theme.Spacing.gap4, 0), h - Theme.Spacing.gap8))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    binding.wrappedValue = (min(max(1 - drag.location.y / h, 0), 1) * 40 - 20).rounded()
                })
            }
            .frame(width: Theme.Spacing.gap16, height: Theme.Metric.SettingsDetail.equalizerTrackHeight)
            .mxrKeyboardFocusable(cornerRadius: Theme.Radius.md) // no system focus ring on click (C1, D028)
            .onKeyPress(.upArrow) { binding.wrappedValue = min(20, binding.wrappedValue + 1); return .handled }
            .onKeyPress(.downArrow) { binding.wrappedValue = max(-20, binding.wrappedValue - 1); return .handled }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue("\(binding.wrappedValue.formatted()) dB")
            .accessibilityAdjustableAction { direction in
                binding.wrappedValue = min(max(binding.wrappedValue + (direction == .increment ? 1 : -1), -20), 20)
            }
            VStack(spacing: Theme.Spacing.gap12) {
                Text(label).mxrTextStyle(Theme.Font.body).foregroundStyle(Theme.Color.fgA3)
                SettingsEqualizerGainEditor(gain: binding, label: label)
            }.frame(height: Theme.Metric.SettingsDetail.equalizerValueGroupHeight)
        }.frame(width: Theme.Metric.SettingsDetail.equalizerBandWidth)
    }
}

private struct SettingsEqualizerGainEditor: View {
    @Binding var gain: Double
    let label: String
    @State private var text = ""
    @State private var invalid = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            TextField("Gain", text: $text).textFieldStyle(.plain).focused($focused).fixedSize()
            Text(" dB")
        }
        .mxrTextStyle(Theme.Font.caption).foregroundStyle(Theme.Color.fgA2)
        .frame(maxWidth: .infinity).frame(height: Theme.Metric.buttonHeight)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        .overlay { if invalid { RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(Theme.Color.accentMain) } }
        .onAppear { reload() }
        .onChange(of: gain) { _, _ in if !focused { reload() } }
        .onChange(of: focused) { _, value in if !value { commit() } }
        .onSubmit(commit)
        .onDisappear(perform: commit)
        .accessibilityLabel("\(label) gain")
        .accessibilityHint(invalid ? "Enter a gain from minus 20 to 20 decibels." : "")
    }

    private func reload() { invalid = false; text = gain.rounded() == gain ? String(format: "%.1f", gain) : gain.formatted() }
    private func commit() {
        guard let value = Double(text), value.isFinite, (-20...20).contains(value) else { invalid = true; return }
        invalid = false
        gain = value
    }
}
