import AppKit
import MXRDesign
import SwiftUI

/// `D.Accents/default`: the nine accents with their accent-dependent tokens and the elements that
/// follow the accent (seek fill and playhead, play button, accent dot, active and two-tone icons).
final class DesignAccentsGallery: NSObject, GalleryProvider {
    @MainActor static func galleryEntries() -> [Any] {
        [GalleryEntry(
            id: "D.Accents/default",
            title: "Accents",
            size: CGSize(width: DesignGalleryLayout.pageWidth, height: DesignGalleryLayout.accentsPageHeight),
            colorScheme: .dark,
            notes: "Specimen page (no single Figma node; compare with Onboarding-1…10, nodes 1902:3670…). Orange uses the Figma styles; other accents follow colors.json derivationRule (AccentPalette.swift)."
        ) {
            DesignAccentsPage()
                .environment(\.colorScheme, .dark)
        }]
    }
}

private struct DesignAccentsPage: View {
    private static let tokens: [Theme.ColorToken] = [
        .accentMain, .accentDim, .accentBright, .accentLogo, .bgAccentBright, .bgAccentDark, .accentRing,
    ]

    var body: some View {
        DesignGalleryPage(
            title: "Accents",
            subtitle: "Accent-dependent tokens per accent (\(Self.tokens.map(\.name).joined(separator: ", "))) and sample elements"
        ) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap12) {
                ForEach(Theme.Accent.allCases) { accent in
                    DesignAccentRow(accent: accent, tokens: Self.tokens)
                        .mxrAccent(accent)
                }
            }
        }
    }
}

private struct DesignAccentRow: View {
    let accent: Theme.Accent
    let tokens: [Theme.ColorToken]

    var body: some View {
        HStack(spacing: Theme.Spacing.gap16) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                Text(accent.rawValue)
                    .mxrTextStyle(.body)
                    .foregroundStyle(Theme.Color.fgA1)
                Text(accent.swatch.hexString)
                    .mxrTextStyle(.caption)
                    .foregroundStyle(Theme.Color.fgA3)
            }
            .frame(width: Theme.Metric.Controls.dialogButton.width, alignment: .leading)

            ForEach(tokens, id: \.self) { token in
                DesignGallerySwatch(fill: ThemeColor(token), height: Theme.Metric.Controls.toggle.height)
                    .frame(width: Theme.Metric.Controls.toggle.width)
            }

            seekSample
            playButton
            MXRIcon(.lists, state: .active)
            MXRIcon(.audio, tone: .twoTone)
            MXRIcon(.videos, state: .selected)
            colorDot
        }
    }

    /// Seek track (`bgB2`, r6) with the `bgAccentBright` fill and the `accentMain` playhead (S07).
    private var seekSample: some View {
        let track = Theme.Metric.ControlBar.seekTrack
        let fill = Theme.Metric.ControlBar.seekFill
        let head = Theme.Metric.ControlBar.playhead
        let inset = (track.height - fill.height) / 2
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: track.radius ?? 0).fill(Theme.Color.bgB2)
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: fill.radius ?? 0)
                    .fill(Theme.Color.bgAccentBright)
                    .frame(width: fill.width, height: fill.height)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: head.radius ?? 0)
                            .fill(Theme.Color.accentMain)
                            .frame(width: head.width, height: head.height)
                    }
            }
            .padding(.leading, inset)
        }
        .frame(width: DesignGalleryLayout.seekSampleWidth, height: track.height)
    }

    /// Play button: `accentMain` fill, glyph in `fgB1` (node 848:1711).
    private var playButton: some View {
        let box = Theme.Metric.ControlBar.playButton
        return MXRIcon(.play, tint: Theme.Color.fgB1)
            .padding(box.padding)
            .frame(width: box.width, height: box.height)
            .background(Theme.Color.accentMain, in: RoundedRectangle(cornerRadius: box.radius ?? 0))
    }

    /// Selected accent dot with its 30 % ring (node 1902:4003: 64 frame, 4 px inside ring, 40 dot).
    private var colorDot: some View {
        let box = Theme.Metric.Dialogs.colorDot
        let ring = Theme.Spacing.gap4
        return Circle()
            .fill(Theme.Color.accentMain)
            .padding(box.padding.top + ring)
            .frame(width: box.width, height: box.height)
            .overlay(Circle().strokeBorder(Theme.Color.accentRing, lineWidth: ring))
            .scaleEffect(Theme.Metric.iconButtonHeight / box.height)
            .frame(width: Theme.Metric.iconButtonHeight, height: Theme.Metric.iconButtonHeight)
    }
}
