import AppKit
import SwiftUI

/// A color token (`Theme.Color.*`). As a `ShapeStyle` it resolves from the environment: the color
/// scheme (dark/light) and the accent set with `.mxrAccent(_:)`. Use it directly with
/// `.foregroundStyle`, `.fill`, `.stroke` and `.background`.
///
/// Where an API needs a `SwiftUI.Color` or `NSColor`, read the accent from the environment
/// (`@Environment(\.mxrAccent)`) and call `color(accent:)` or `nsColor(accent:)`; both still follow
/// the appearance (dark/light) of the place they are drawn.
public struct ThemeColor: ShapeStyle, Hashable, Sendable, CustomStringConvertible {
    public let token: Theme.ColorToken

    public init(_ token: Theme.ColorToken) {
        self.token = token
    }

    /// Whether the value changes with `Theme.Accent`.
    public var isAccentDependent: Bool { token.isAccentDependent }

    public var description: String { "Theme.Color.\(token.name)" }

    /// `ShapeStyle` resolution from the environment's color scheme and `mxrAccent`.
    public func resolve(in environment: EnvironmentValues) -> SwiftUI.Color {
        value(scheme: environment.colorScheme, accent: environment.mxrAccent,
              contrast: environment.colorSchemeContrast).color
    }

    /// The token value for a color scheme, accent and the user's Increase Contrast preference.
    public func value(scheme: ColorScheme, accent: Theme.Accent = .orange,
                      contrast: ColorSchemeContrast = .standard) -> Theme.RGBA {
        Palette.value(token, dark: scheme != .light, accent: accent, increasedContrast: contrast == .increased)
    }

    /// A SwiftUI color for `accent` that follows the appearance it is drawn in.
    public func color(accent: Theme.Accent) -> SwiftUI.Color {
        SwiftUI.Color(nsColor: nsColor(accent: accent))
    }

    /// A fixed SwiftUI color for a color scheme and accent.
    public func color(scheme: ColorScheme, accent: Theme.Accent) -> SwiftUI.Color {
        value(scheme: scheme, accent: accent).color
    }

    /// An AppKit color for `accent` that follows the appearance it is drawn in (dark/light) and the
    /// user's Increase Contrast setting, like the SwiftUI path.
    public func nsColor(accent: Theme.Accent) -> NSColor {
        nsColor(accent: accent, increasedContrast: { appearance in
            appearance.mxrIsHighContrast || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        })
    }

    /// `nsColor(accent:)` with the Increase Contrast source injected (tests; AppKit cannot create the
    /// high-contrast appearances outside the system setting).
    public func nsColor(accent: Theme.Accent,
                        increasedContrast: @escaping @Sendable (NSAppearance) -> Bool) -> NSColor {
        let token = token
        return NSColor(name: nil) { appearance in
            Palette.value(token, dark: appearance.mxrIsDark, accent: accent,
                          increasedContrast: increasedContrast(appearance)).nsColor
        }
    }
}

extension NSAppearance {
    /// Whether this appearance is a dark one (`darkAqua` and its vibrant / high-contrast forms).
    public var mxrIsDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Whether this is a high-contrast appearance (System Settings > Accessibility > Increase Contrast).
    public var mxrIsHighContrast: Bool {
        let match = bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        return match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
    }
}

/// Resolved token values for every scheme × accent, built once from the generated tables.
enum Palette {
    private static let accents = Theme.Accent.allCases
    /// `[scheme][accentIndex][token.rawValue]`; scheme 0 = dark, 1 = light.
    private static let tables: [[[Theme.RGBA]]] = [
        accents.map { AccentPalette.table(base: GeneratedPalette.dark, accent: $0) },
        accents.map { AccentPalette.table(base: GeneratedPalette.light, accent: $0) },
    ]
    private static let accentIndex: [Theme.Accent: Int] =
        Dictionary(uniqueKeysWithValues: accents.enumerated().map { ($1, $0) })

    static func value(_ token: Theme.ColorToken, dark: Bool, accent: Theme.Accent,
                      increasedContrast: Bool = false) -> Theme.RGBA {
        // Increase Contrast keeps the hierarchy but lifts the dim secondary text (fgA3) to fgA1.
        let resolved = increasedContrast && token == .fgA3 ? Theme.ColorToken.fgA1 : token
        return tables[dark ? 0 : 1][accentIndex[accent] ?? 0][resolved.rawValue]
    }
}
