import AppKit
import MXRDesign
import SwiftUI

/// `D.Icons/mono` and `D.Icons/twoTone`: every icon of the Figma `Icon` set (42:356) at 24 pt,
/// with all its states, drawn from the asset catalog by `MXRIcon`.
final class DesignIconsGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        let mono = MXRIcon.Name.allCases.filter { name in
            MXRIcon.variants(of: name).contains { $0.tone == .mono }
        }
        let twoTone = MXRIcon.Name.allCases.filter { name in
            MXRIcon.variants(of: name).contains { $0.tone == .twoTone }
        }
        return [
            GalleryEntry(
                id: "D.Icons/mono",
                title: "Icons — mono",
                size: CGSize(width: DesignGalleryLayout.pageWidth,
                             height: DesignIconsPage.height(for: mono.count, tone: .mono)),
                colorScheme: .dark,
                notes: "Specimen page of the Figma Icon set (42:356, render Icon.png). Mono icons: default (FG/A2), active (Accent/Main), selected; plus the tint options of MXRIcon."
            ) {
                DesignIconsPage(title: "Icons — mono", names: mono, tone: .mono)
                    .environment(\.colorScheme, .dark)
            },
            GalleryEntry(
                id: "D.Icons/twoTone",
                title: "Icons — two-tone",
                size: CGSize(width: DesignGalleryLayout.pageWidth,
                             height: DesignIconsPage.height(for: twoTone.count, tone: .twoTone)),
                colorScheme: .dark,
                notes: "Specimen page of the Figma Icon set (42:356, render Icon.png). Two-tone menu icons (accent part in Accent/Dim) next to their mono default."
            ) {
                DesignIconsPage(title: "Icons — two-tone", names: twoTone, tone: .twoTone)
                    .environment(\.colorScheme, .dark)
            },
        ]
    }
}

private struct DesignIconsPage: View {
    let title: String
    let names: [MXRIcon.Name]
    let tone: MXRIcon.Tone

    static func height(for count: Int, tone: MXRIcon.Tone) -> CGFloat {
        let columns = DesignGalleryLayout.iconColumns
        let rows = (count + columns - 1) / columns
        let grid = CGFloat(rows) * (DesignGalleryLayout.iconCellHeight + Theme.Spacing.gap16)
        let tinting = tone == .mono ? DesignGalleryLayout.iconTintSectionHeight : 0
        return DesignGalleryLayout.pageHeaderHeight + tinting + grid
    }

    var body: some View {
        DesignGalleryPage(
            title: title,
            subtitle: tone == .mono
                ? "MXRIcon(.<name>, state:) · default · active · selected (only states Figma defines; an empty well is an empty Figma frame)"
                : "MXRIcon(.<name>) and MXRIcon(.<name>, tone: .twoTone[, state:]) · accent part follows .mxrAccent"
        ) {
            if tone == .mono {
                DesignIconTintSection()
            }
            DesignGalleryGrid(items: names, columns: DesignGalleryLayout.iconColumns) { name in
                DesignIconCell(name: name, tone: tone)
                    .frame(height: DesignGalleryLayout.iconCellHeight, alignment: .top)
            }
        }
    }
}

/// How the gray artwork is tinted: the default, a token, `nil` (inherits the foreground style set
/// on the icon or an ancestor) and a two-tone icon whose base inherits while its accent part keeps
/// `accentDim`.
private struct DesignIconTintSection: View {
    var body: some View {
        DesignGallerySection(title: "Tinting the gray artwork") {
            HStack(alignment: .top, spacing: Theme.Spacing.gap16) {
                sample("MXRIcon(.play)", "default tint: fgA2") {
                    MXRIcon(.play)
                }
                sample("MXRIcon(.play, tint: Theme.Color.fg1)", "any token or ShapeStyle") {
                    MXRIcon(.play, tint: Theme.Color.fg1)
                }
                sample("MXRIcon(.play, tint: nil)", ".foregroundStyle(accentBright) on an ancestor") {
                    HStack { MXRIcon(.play, tint: nil) }
                        .foregroundStyle(Theme.Color.accentBright)
                }
                sample("MXRIcon(.audio, tone: .twoTone, tint: nil)", ".foregroundStyle(fg1): base only") {
                    MXRIcon(.audio, tone: .twoTone, tint: nil)
                        .foregroundStyle(Theme.Color.fg1)
                }
            }
        }
    }

    private func sample<Icon: View>(_ code: String, _ note: String, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap8) {
            icon()
                .padding(Theme.Metric.ControlBar.iconButton.padding)
                .background(Theme.Color.bgB2, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            Text(code)
                .mxrTextStyle(.caption)
                .foregroundStyle(Theme.Color.fgA1)
            Text(note)
                .mxrTextStyle(.caption)
                .foregroundStyle(Theme.Color.fgA3)
        }
        .frame(width: DesignGalleryLayout.iconTintCellWidth, alignment: .topLeading)
    }
}

private struct DesignIconCell: View {
    let name: MXRIcon.Name
    let tone: MXRIcon.Tone

    /// Variants to show: all of this tone; for two-tone also the mono default for comparison.
    private var shown: [MXRIcon.Variant] {
        let all = MXRIcon.variants(of: name)
        let mine = all.filter { $0.tone == tone }
        if tone == .twoTone, let mono = all.first(where: { $0.tone == .mono && $0.state == .default }) {
            return [mono] + mine
        }
        return mine
    }

    private func label(_ variant: MXRIcon.Variant) -> String {
        if tone == .mono {
            return variant.state.rawValue
        }
        // Non-breaking hyphen: a long states line wraps at " · ", not inside "2-tone".
        let toneName = variant.tone == .twoTone ? "2\u{2011}tone" : "mono"
        return variant.state == .default ? toneName : "\(toneName)/\(variant.state.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap8) {
            HStack(spacing: Theme.Spacing.gap12) {
                ForEach(shown, id: \.self) { variant in
                    MXRIcon(name, tone: variant.tone, state: variant.state)
                        .padding(Theme.Metric.ControlBar.iconButton.padding)
                        .background(Theme.Color.bgB2, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
            Text(name.rawValue)
                .mxrTextStyle(.body)
                .foregroundStyle(Theme.Color.fgA1)
                .lineLimit(1)
            // Up to two lines: "mono · 2-tone · 2-tone/selected" is wider than a cell.
            Text(shown.map(label).joined(separator: " · "))
                .mxrTextStyle(.caption)
                .foregroundStyle(Theme.Color.fgA3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: DesignGalleryLayout.iconCellWidth, alignment: .topLeading)
    }
}
