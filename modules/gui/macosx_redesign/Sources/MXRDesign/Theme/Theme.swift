import AppKit
import SwiftUI

/// Namespace for every design token. The values live in `Generated/Tokens.swift`, produced by
/// `tools/gen-tokens.py` from `redesign/design/tokens/`; this file holds the value types.
///
/// - `Theme.Color.*`: colors (`ThemeColor`), resolved per color scheme and accent.
/// - `Theme.Font.*`: text styles (`Theme.TextStyle`); apply with `.mxrTextStyle(_:)`.
/// - `Theme.Metric.*`, `Theme.Radius.*`, `Theme.Spacing.*`, `Theme.Stroke.*`: sizes in points.
/// - `Theme.Effect.*`, `Theme.Gradient.*`: shadows, blurs and gradients.
public enum Theme {}

// MARK: - Theme mode

extension Theme {
    /// The interface theme the user picks (onboarding, Settings > General). Stored in the VLC
    /// option `macosx-redesign-theme` as the raw value.
    public enum Mode: String, CaseIterable, Sendable, Identifiable {
        case dark
        case light
        /// Follow the macOS appearance.
        case system

        public var id: String { rawValue }

        /// The SwiftUI color scheme to force, or `nil` to follow the system.
        public var colorScheme: ColorScheme? {
            switch self {
            case .dark: .dark
            case .light: .light
            case .system: nil
            }
        }

        /// The AppKit appearance to set on windows (`NSWindow.appearance`), or `nil` to follow the system.
        public var nsAppearance: NSAppearance? {
            switch self {
            case .dark: NSAppearance(named: .darkAqua)
            case .light: NSAppearance(named: .aqua)
            case .system: nil
            }
        }
    }
}

// MARK: - Color value

extension Theme {
    /// A color as stored in the tokens: gamma-encoded sRGB components and alpha, each in 0...1.
    public struct RGBA: Hashable, Sendable, CustomStringConvertible {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }

        /// Creates a color from `0xRRGGBB`.
        public init(hex: UInt32, alpha: Double = 1) {
            self.init(red: Double((hex >> 16) & 0xFF) / 255,
                      green: Double((hex >> 8) & 0xFF) / 255,
                      blue: Double(hex & 0xFF) / 255,
                      alpha: alpha)
        }

        /// `#RRGGBB`, ignoring alpha.
        public var hexString: String {
            func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        }

        /// `#RRGGBB` or `#RRGGBB@alpha` when not opaque.
        public var description: String {
            alpha >= 1 ? hexString : "\(hexString)@\((alpha * 100).rounded() / 100)"
        }

        /// The same color with its alpha multiplied by `opacity`.
        public func opacity(_ opacity: Double) -> RGBA {
            RGBA(red: red, green: green, blue: blue, alpha: alpha * opacity)
        }

        /// This color composited (source-over, in sRGB) on an opaque `background`.
        public func composited(over background: RGBA) -> RGBA {
            let a = alpha + background.alpha * (1 - alpha)
            guard a > 0 else { return RGBA(red: 0, green: 0, blue: 0, alpha: 0) }
            func mix(_ c: Double, _ b: Double) -> Double { (c * alpha + b * background.alpha * (1 - alpha)) / a }
            return RGBA(red: mix(red, background.red), green: mix(green, background.green),
                        blue: mix(blue, background.blue), alpha: a)
        }

        /// SwiftUI color in the sRGB space.
        public var color: SwiftUI.Color {
            SwiftUI.Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
        }

        /// AppKit color in the sRGB space.
        public var nsColor: NSColor {
            NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }

        /// Core Graphics color in the sRGB space.
        public var cgColor: CGColor {
            CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        }
    }

    /// One stop of a gradient token.
    public struct GradientStop: Hashable, Sendable {
        public var color: RGBA
        /// Position along the gradient, 0...1.
        public var location: Double

        public init(color: RGBA, location: Double) {
            self.color = color
            self.location = location
        }
    }
}

extension Array where Element == Theme.GradientStop {
    /// The stops as a SwiftUI gradient.
    public var gradient: SwiftUI.Gradient {
        SwiftUI.Gradient(stops: map { .init(color: $0.color.color, location: $0.location) })
    }
}

// MARK: - Metrics value types

extension Theme {
    /// Padding as Figma writes it, mapped to leading/trailing (Figma left/right).
    public struct Insets: Hashable, Sendable {
        public var top: CGFloat
        public var leading: CGFloat
        public var bottom: CGFloat
        public var trailing: CGFloat

        public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
            self.top = top
            self.leading = leading
            self.bottom = bottom
            self.trailing = trailing
        }

        public static let zero = Insets(top: 0, leading: 0, bottom: 0, trailing: 0)

        /// For SwiftUI's `.padding(_:)`.
        public var edgeInsets: EdgeInsets {
            EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
        }

        /// For AppKit (`NSStackView.edgeInsets`, …); assumes left-to-right layout.
        public var nsEdgeInsets: NSEdgeInsets {
            NSEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
        }

        public var horizontal: CGFloat { leading + trailing }
        public var vertical: CGFloat { top + bottom }
    }

    /// Per-corner radii (Figma `rectangleCornerRadii`).
    public struct CornerRadii: Hashable, Sendable {
        public var topLeading: CGFloat
        public var topTrailing: CGFloat
        public var bottomTrailing: CGFloat
        public var bottomLeading: CGFloat

        public init(topLeading: CGFloat, topTrailing: CGFloat, bottomTrailing: CGFloat, bottomLeading: CGFloat) {
            self.topLeading = topLeading
            self.topTrailing = topTrailing
            self.bottomTrailing = bottomTrailing
            self.bottomLeading = bottomLeading
        }

        /// For `UnevenRoundedRectangle(cornerRadii:)`.
        public var rectangleCornerRadii: RectangleCornerRadii {
            RectangleCornerRadii(topLeading: topLeading, bottomLeading: bottomLeading,
                                 bottomTrailing: bottomTrailing, topTrailing: topTrailing)
        }
    }

    /// Geometry of a named Figma frame: size, corner radius, auto-layout gap and padding.
    public struct Box: Hashable, Sendable {
        /// Figma node id (see `redesign/design/figma/INDEX.md`).
        public var node: String
        public var width: CGFloat
        public var height: CGFloat
        /// Uniform corner radius, if the frame has one.
        public var radius: CGFloat?
        /// Per-corner radii, if the corners differ.
        public var radii: CornerRadii?
        /// Auto-layout item spacing.
        public var gap: CGFloat
        public var padding: Insets

        public init(node: String, width: CGFloat, height: CGFloat, radius: CGFloat? = nil, radii: CornerRadii? = nil,
                    gap: CGFloat = 0, padding: Insets = .zero) {
            self.node = node
            self.width = width
            self.height = height
            self.radius = radius
            self.radii = radii
            self.gap = gap
            self.padding = padding
        }

        public var size: CGSize { CGSize(width: width, height: height) }
    }

    /// A drop shadow as Figma defines it (offset, blur, spread, color).
    public struct Shadow: Hashable, Sendable {
        public var x: CGFloat
        public var y: CGFloat
        /// Figma/CSS blur. SwiftUI and Core Animation take half of it as the radius (`radius`).
        public var blur: CGFloat
        /// Figma spread. SwiftUI shadows have no spread; `mxrShadow` ignores it.
        public var spread: CGFloat
        public var color: RGBA

        public init(x: CGFloat, y: CGFloat, blur: CGFloat, spread: CGFloat, color: RGBA) {
            self.x = x
            self.y = y
            self.blur = blur
            self.spread = spread
            self.color = color
        }

        /// The SwiftUI / `CALayer.shadowRadius` equivalent of the Figma blur.
        public var radius: CGFloat { blur / 2 }
    }
}

extension View {
    /// Pads the view with token insets.
    public func padding(_ insets: Theme.Insets) -> some View {
        padding(insets.edgeInsets)
    }

    /// Applies a Figma shadow token (`Theme.Effect.*`). Spread is not supported by SwiftUI and is ignored.
    public func mxrShadow(_ shadow: Theme.Shadow) -> some View {
        self.shadow(color: shadow.color.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
