import MXRCore
import MXRDesign
import SwiftUI

/// The Figma segmented control (Settings ▸ Theme, 3046:9871): equal segments on a BG/B2 track,
/// the selected one in the accent tint. Shared by Settings and the open/convert dialogs.
struct SettingsSegmentedControl<Value: Hashable>: View {
    let choices: [(value: Value, title: String)]
    let selection: Value?
    let select: (Value) -> Void
    var label = ""

    var body: some View {
        HStack(spacing: Theme.Spacing.gap2) {
            ForEach(choices, id: \.value) { choice in
                let selected = selection == choice.value
                Button { select(choice.value) } label: {
                    Text(choice.title).mxrTextStyle(Theme.Font.body)
                        .foregroundStyle(selected ? AnyShapeStyle(MXRAccentLabel()) : AnyShapeStyle(MXRInactiveSegmentLabel()))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity).frame(height: Theme.Metric.SettingsDetail.controlInnerHeight)
                        .background(selected ? Theme.Color.bgAccentBright : Theme.Color.bgA4, in: .rect(cornerRadius: Theme.Radius.md))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(Theme.Spacing.gap2)
        .background(Theme.Color.bgB2, in: .rect(cornerRadius: Theme.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Accent text drawn on the accent tint (selected segment, ON label, primary button). In Light the
/// accent on its tint is about 1.6:1, so Light writes the label in FG/1 and the tint alone marks
/// the selection (D032); Dark keeps the Figma accent text.
struct MXRAccentLabel: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        (environment.colorScheme == .light ? Theme.Color.fg1 : Theme.Color.accentMain).resolve(in: environment)
    }
}

/// Unselected segment labels. Dark keeps Figma's FG/A3; on Light's BG/A4 FG/A3 is about 2.4:1,
/// so Light writes them in FG/2 (D032) and the accent tint alone marks the selected segment.
struct MXRInactiveSegmentLabel: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        (environment.colorScheme == .light ? Theme.Color.fg2 : Theme.Color.fgA3).resolve(in: environment)
    }
}
