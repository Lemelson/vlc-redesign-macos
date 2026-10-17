import Foundation

/// Derives the accent-dependent tokens for every accent.
///
/// Figma names the full set of shades only for orange (`Accent/Main`, `Bright`, `DIm`, `Logo`,
/// `BG/Accent Bright`, `BG/Accent Dark`, in a Dark and a Light version). For the eight other accents
/// the designer applied the swatch to the same elements (colors.json `accentSwatches`, verified in
/// the dark Onboarding frames 1902:4020 … 1902:6465). The rule, recorded in colors.json
/// `derivationRule`:
///
/// - `accentMain`, `accentLogo`: the swatch itself (dark theme).
/// - `bgAccentBright` (seek-bar fill): `accentMain` at 24 % opacity, except blue at 30 %
///   (Figma node 1925:9940 in onboarding frame 1902:5245).
/// - `accentRing` (selected accent dot): `accentMain` at 30 % opacity (also true for orange).
/// - glyphs on the accent: `fgB1` (not accent-dependent).
///
/// Every other shade, and every shade of the light theme, has no Figma value for the other accents.
/// One rule covers them all: each shade keeps the swatch's hue and scales its saturation and
/// brightness (HSB) by the factors that turn the orange swatch (#D37918, = `Dark/Accent/Main`) into
/// orange's named style for that token and theme. So in the light theme every accent is brightened
/// the way `Light/Accent/Main` (#E8851A) brightens orange, and `accentLogo` is darkened the way
/// `Light/Accent/Logo` (#C2711A) is. Applied to orange the rule reproduces the named styles; orange
/// itself always uses the Figma values. Provisional for the light theme (no light Figma frame shows
/// another accent); see NOTES.md.
enum AccentPalette {
    /// Tokens derived from the swatch by orange's HSB ratios.
    private static let scaledTokens: [Theme.ColorToken] = [
        .accentMain, .accentLogo, .accentDim, .accentBright, .bgAccentDark,
    ]

    /// The token table for `accent`, starting from the generated table of one theme (orange values).
    static func table(base: [Theme.RGBA], accent: Theme.Accent) -> [Theme.RGBA] {
        var table = base
        guard accent != .orange else { return table }
        let swatch = accent.swatch
        let reference = Theme.Accent.orange.swatch
        for token in scaledTokens {
            let orange = base[token.rawValue]
            // Where orange's style is the swatch itself (dark Main and Logo) the accent's is too.
            table[token.rawValue] = orange.sameColor(as: reference)
                ? swatch.opacity(orange.alpha)
                : HSB(swatch).scaled(from: HSB(reference), to: HSB(orange)).rgba(alpha: orange.alpha)
        }
        let main = table[Theme.ColorToken.accentMain.rawValue]
        table[Theme.ColorToken.bgAccentBright.rawValue] = main.opacity(accent.derivedFillAlpha)
        table[Theme.ColorToken.accentRing.rawValue] = main.opacity(base[Theme.ColorToken.accentRing.rawValue].alpha)
        return table
    }

    /// Hue/saturation/brightness of an sRGB color.
    struct HSB {
        var hue: Double
        var saturation: Double
        var brightness: Double

        init(hue: Double, saturation: Double, brightness: Double) {
            self.hue = hue
            self.saturation = saturation
            self.brightness = brightness
        }

        init(_ c: Theme.RGBA) {
            let maxC = max(c.red, c.green, c.blue)
            let minC = min(c.red, c.green, c.blue)
            let delta = maxC - minC
            brightness = maxC
            saturation = maxC > 0 ? delta / maxC : 0
            var h = 0.0
            if delta > 0 {
                if maxC == c.red {
                    h = (c.green - c.blue) / delta
                } else if maxC == c.green {
                    h = (c.blue - c.red) / delta + 2
                } else {
                    h = (c.red - c.green) / delta + 4
                }
                h /= 6
                if h < 0 { h += 1 }
            }
            hue = h
        }

        /// Keeps this hue; scales saturation and brightness by `target / reference`.
        func scaled(from reference: HSB, to target: HSB) -> HSB {
            func ratio(_ t: Double, _ r: Double) -> Double { r > 0 ? t / r : 1 }
            return HSB(hue: hue,
                       saturation: min(max(saturation * ratio(target.saturation, reference.saturation), 0), 1),
                       brightness: min(max(brightness * ratio(target.brightness, reference.brightness), 0), 1))
        }

        func rgba(alpha: Double) -> Theme.RGBA {
            let h = hue * 6
            let i = Int(h.rounded(.down)) % 6
            let f = h - h.rounded(.down)
            let v = brightness
            let p = v * (1 - saturation)
            let q = v * (1 - saturation * f)
            let t = v * (1 - saturation * (1 - f))
            let (r, g, b): (Double, Double, Double)
            switch i {
            case 0: (r, g, b) = (v, t, p)
            case 1: (r, g, b) = (q, v, p)
            case 2: (r, g, b) = (p, v, t)
            case 3: (r, g, b) = (p, q, v)
            case 4: (r, g, b) = (t, p, v)
            default: (r, g, b) = (v, p, q)
            }
            return Theme.RGBA(red: r, green: g, blue: b, alpha: alpha)
        }
    }
}

private extension Theme.RGBA {
    /// Same RGB components (alpha ignored), to the precision of the 8-bit token values.
    func sameColor(as other: Theme.RGBA) -> Bool {
        hexString == other.hexString
    }
}
