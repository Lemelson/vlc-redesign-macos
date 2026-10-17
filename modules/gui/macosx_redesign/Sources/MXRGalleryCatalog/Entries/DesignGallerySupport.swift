import MXRDesign
import SwiftUI

// Shared building blocks of the design-system specimen pages (`D.*` gallery entries). These pages
// show the tokens themselves; their own layout sizes are specimen-page values, not product UI, and
// all of them live in `DesignGalleryLayout` (the only literal sizes in the D.* pages).

/// Specimen-page layout values (not design tokens). Only `D.*` pages may use them.
enum DesignGalleryLayout {
    /// Canvas width of every `D.*` page.
    static let pageWidth: CGFloat = 1200
    /// Height of a color swatch.
    static let swatchHeight: CGFloat = 56
    /// Width of a swatch cell (6 per row at `pageWidth`).
    static let cellWidth: CGFloat = 176
    /// Width of the label column on the typography and accent pages.
    static let labelColumn: CGFloat = 240

    /// Canvas heights of the fixed-content pages (each fits its content at `pageWidth`).
    static let colorsPageHeight: CGFloat = 1290
    static let accentsPageHeight: CGFloat = 540
    static let typographyPageHeight: CGFloat = 1240

    /// Height of a page's title block, padding and the gap below it (`D.Icons/*` height math).
    static let pageHeaderHeight: CGFloat = 110
    /// Icon cells: 7 per row; room for three icon wells, the name and two lines of states.
    static let iconColumns = 7
    static let iconCellWidth: CGFloat = 150
    static let iconCellHeight: CGFloat = 108
    /// Height of the tinting section on `D.Icons/mono` (title, one row of samples and labels).
    static let iconTintSectionHeight: CGFloat = 144
    /// Width of a tint sample cell on `D.Icons/mono`.
    static let iconTintCellWidth: CGFloat = 220

    /// Width of the seek-bar sample on `D.Accents` (the track around a `seekFill`-sized fill).
    static let seekSampleWidth: CGFloat = 148
}

/// A `D.*` page: title, subtitle and content on the window background (`bgA3`).
struct DesignGalleryPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.gap4) {
                Text(title)
                    .mxrTextStyle(.homeSectionTitle)
                    .foregroundStyle(Theme.Color.fgA1)
                Text(subtitle)
                    .mxrTextStyle(.caption)
                    .foregroundStyle(Theme.Color.fgA3)
            }
            content
        }
        .padding(Theme.Spacing.gap20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Color.bgA3)
    }
}

/// A titled group on a `D.*` page.
struct DesignGallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.gap10) {
            // Settings section headers use fg2, which is unreadable in the light palette (NOTES.md);
            // fgA1 keeps both specimen themes legible.
            Text(title)
                .mxrTextStyle(.sectionHeader)
                .foregroundStyle(Theme.Color.fgA1)
            content
        }
    }
}

/// Lays items out in rows of `columns` with `Grid` (renders eagerly, unlike lazy grids).
struct DesignGalleryGrid<Item: Hashable, Cell: View>: View {
    let items: [Item]
    var columns: Int = 6
    @ViewBuilder let cell: (Item) -> Cell

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Theme.Spacing.gap16, verticalSpacing: Theme.Spacing.gap16) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                GridRow {
                    ForEach(items[start..<min(start + columns, items.count)], id: \.self) { item in
                        cell(item)
                    }
                }
            }
        }
    }
}

/// Checkerboard behind translucent swatches, so alpha is visible.
struct DesignGalleryCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let square = Theme.Spacing.gap8
            var light = Path()
            for row in 0..<Int((size.height / square).rounded(.up)) {
                for column in 0..<Int((size.width / square).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    light.addRect(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square))
                }
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .style(Theme.Color.bgB2))
            context.fill(light, with: .style(Theme.Color.fgA4))
        }
    }
}

/// A filled swatch with a checkerboard behind it and a hairline outline.
struct DesignGallerySwatch<Fill: ShapeStyle>: View {
    let fill: Fill
    var height: CGFloat = DesignGalleryLayout.swatchHeight

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg)
        ZStack {
            DesignGalleryCheckerboard()
            shape.fill(fill)
        }
        .frame(height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Color.dividerBright, lineWidth: Theme.Stroke.hairline))
    }
}
