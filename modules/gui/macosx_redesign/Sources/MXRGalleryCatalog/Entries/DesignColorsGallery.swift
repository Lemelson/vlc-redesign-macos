import AppKit
import MXRDesign
import SwiftUI

/// `D.Colors/dark`, `D.Colors/light`: every color token (`Theme.Color.*`) as a swatch with its
/// value in that theme and its Figma style.
final class DesignColorsGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        [ColorScheme.dark, .light].map { scheme in
            let name = scheme == .dark ? "dark" : "light"
            return GalleryEntry(
                id: "D.Colors/\(name)",
                title: "Colors (\(name))",
                size: CGSize(width: DesignGalleryLayout.pageWidth, height: DesignGalleryLayout.colorsPageHeight),
                colorScheme: scheme,
                notes: "Theme.Color tokens from redesign/design/tokens/colors.json, \(name) theme, orange accent."
            ) {
                DesignColorsPage(scheme: scheme)
                    .environment(\.colorScheme, scheme)
            }
        }
    }
}

private struct DesignColorsPage: View {
    let scheme: ColorScheme

    private static let groups: [(String, [Theme.ColorToken])] = {
        var groups: [(String, [Theme.ColorToken])] = [
            ("Backgrounds", [.bgA1, .bgA2, .bgA3, .bgA3Transparent, .bgA4, .bgA5,
                             .bgB1, .bgB1Transparent, .bgB2, .bgB2Transparent]),
            ("Foreground and dividers", [.fg1, .fg2, .fgA1, .fgA2, .fgA3, .fgA4, .fgB1, .dividerBright, .dividerDim]),
            ("Accent (orange; see D.Accents)", [.accentMain, .accentDim, .accentBright, .accentLogo,
                                                .bgAccentBright, .bgAccentDark, .accentRing]),
            ("Raw colors (not bound to a Figma style)", [.iconHover, .thumbPlaceholder, .volumeBody, .imageOverlay,
                                                        .homeCard, .subtitleCue, .swatchOutline, .keycapShadow]),
            ("Volume cone (Player / Player - Light)", [.volumeConeTrack, .volumeConeOverlay]),
        ]
        let listed = Set(groups.flatMap(\.1))
        let rest = Theme.ColorToken.allCases.filter { !listed.contains($0) }
        if !rest.isEmpty {
            groups.append(("Other", rest))
        }
        return groups
    }()

    var body: some View {
        DesignGalleryPage(
            title: "Colors — \(scheme == .dark ? "Dark" : "Light")",
            subtitle: "Theme.Color.<token> · value in this theme · Figma paint style"
        ) {
            ForEach(Self.groups, id: \.0) { group in
                DesignGallerySection(title: group.0) {
                    DesignGalleryGrid(items: group.1) { token in
                        DesignColorCell(token: token, scheme: scheme)
                    }
                }
            }
        }
    }
}

private struct DesignColorCell: View {
    let token: Theme.ColorToken
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
            DesignGallerySwatch(fill: ThemeColor(token))
            Text(token.name)
                .mxrTextStyle(.body)
                .foregroundStyle(Theme.Color.fgA1)
            Text(ThemeColor(token).value(scheme: scheme).description)
                .mxrTextStyle(.caption)
                .foregroundStyle(Theme.Color.fgA2)
            Text(token.figmaStyle ?? (token.isAccentDependent ? "derived" : "raw"))
                .mxrTextStyle(.caption)
                .foregroundStyle(Theme.Color.fgA3)
        }
        .frame(width: DesignGalleryLayout.cellWidth, alignment: .leading)
    }
}
