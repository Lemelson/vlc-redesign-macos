import AppKit
import MXRDesign
import SwiftUI

/// `D.Typography/default`: every text style (`Theme.Font.*`) with its Figma sample, applied with
/// `.mxrTextStyle(_:)`. The tinted box behind each specimen is the text box, so its height shows
/// the Figma line height (two lines where the line height is fixed, to show line spacing).
final class DesignTypographyGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        [GalleryEntry(
            id: "D.Typography/default",
            title: "Typography",
            size: CGSize(width: DesignGalleryLayout.pageWidth, height: DesignGalleryLayout.typographyPageHeight),
            colorScheme: .dark,
            notes: "Theme.Font from redesign/design/tokens/typography.json (Inter 3.19, DM Mono)."
        ) {
            DesignTypographyPage()
                .environment(\.colorScheme, .dark)
        }]
    }
}

private struct DesignTypographyPage: View {
    var body: some View {
        DesignGalleryPage(
            title: "Typography",
            subtitle: "Theme.Font.<style> · family weight size/line height · sample from Figma, text box tinted"
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap12) {
                ForEach(Theme.TextStyle.all) { style in
                    DesignTypeRow(style: style)
                }
            }
        }
    }
}

private struct DesignTypeRow: View {
    let style: Theme.TextStyle

    private var fixedLineHeight: Bool { style.extraLineSpacing > 0.5 }

    private var metrics: String {
        func number(_ value: CGFloat) -> String {
            value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        }
        return "\(style.family.rawValue) \(style.weight) · \(number(style.size))/\(number(style.lineHeight))"
            + (fixedLineHeight ? "" : " (auto)")
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.gap20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                Text(style.name)
                    .mxrTextStyle(.body)
                    .foregroundStyle(Theme.Color.fgA1)
                Text(metrics)
                    .mxrTextStyle(.caption)
                    .foregroundStyle(Theme.Color.fgA3)
            }
            .frame(width: DesignGalleryLayout.labelColumn, alignment: .leading)

            Text(fixedLineHeight ? "\(style.figmaSample)\n\(style.figmaSample)" : style.figmaSample)
                .mxrTextStyle(style)
                .foregroundStyle(Theme.Color.fg1)
                .background(Theme.Color.bgA1)
                .fixedSize()
        }
    }
}
