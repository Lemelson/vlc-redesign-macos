import AppKit
import SwiftUI

/// A Figma icon (component set `Icon`, 42:356) drawn from the vector asset catalog.
///
/// Each icon is split into layers by color (see `tools/gen-icons.py`); every layer is a template
/// image tinted by its role, so accent parts follow `.mxrAccent(_:)`:
/// - gray artwork (`Dark/FG/A2`) uses `tint` (default `Theme.Color.fgA2`; any `ShapeStyle` works;
///   `nil` leaves it unstyled, so it takes the foreground style set around the icon);
/// - `Accent/Main` parts use `Theme.Color.accentMain`, two-tone `Accent/DIm` parts `Theme.Color.accentDim`,
///   and the VLC cone (`Accent/Logo` in Figma) `Theme.Color.accentLogo`, whatever `tint` says;
/// - thumbnail and divider artwork keep their token colors.
///
/// ```swift
/// MXRIcon(.subtitles)                          // mono, FG/A2
/// MXRIcon(.audio, tone: .twoTone)              // menu icon, accent part in Accent/Dim
/// MXRIcon(.lists, state: .active)              // accent
/// MXRIcon(.play, tint: Theme.Color.fgB1)       // glyph on an accent fill
/// MXRIcon(.close, tint: nil)                   // inherits the surrounding foreground style
///     .foregroundStyle(isHovered ? Theme.Color.fg1 : Theme.Color.fgA2)
/// ```
///
/// Missing variants fall back: a missing two-tone draws the mono icon; a missing `.active` draws the
/// default artwork in the accent color; a missing `.selected` draws the default artwork.
/// Variants Figma leaves empty draw nothing in their 24 pt slot, as in Figma: the unchecked menu row is
/// `MXRIcon(.check)` (empty) and the checked one `MXRIcon(.check, state: .active)`.
/// Icons are decorative (hidden from accessibility); label the control that contains them.
///
/// With Differentiate Without Color on, an `.active` icon that Figma draws only by recoloring (no
/// filled `.active` variant: repeat, shuffle, PiP, ...) also gets an `iconHover` tile behind it, so
/// the on state does not depend on the accent hue alone.
public struct MXRIcon: View {
    /// Mono = functional icons; two-tone = decorative menu icons with an accent part.
    public enum Tone: String, CaseIterable, Sendable {
        case mono
        case twoTone
    }

    /// Figma `state` axis.
    public enum State: String, CaseIterable, Sendable {
        case `default`
        /// Accent-colored (current item, toggled on).
        case active
        /// The current item in the library rail and menus.
        case selected
    }

    /// One Figma variant: its layers in drawing order.
    public struct Variant: Sendable, Hashable {
        public let tone: Tone
        public let state: State
        /// Figma node id of the variant.
        public let figmaNode: String
        /// File in `redesign/design/figma/icons-svg/`; empty for a variant Figma leaves empty (no layers).
        public let sourceFile: String
        let layers: [Layer]
        /// Artwork extent in icon units; larger than 24×24 only where an accent dot overflows the frame.
        public let canvas: CGSize

        init(tone: Tone, state: State, figmaNode: String, sourceFile: String, layers: [Layer],
             canvas: CGSize = CGSize(width: 24, height: 24)) {
            self.tone = tone
            self.state = state
            self.figmaNode = figmaNode
            self.sourceFile = sourceFile
            self.layers = layers
            self.canvas = canvas
        }

        /// Number of color layers.
        public var layerCount: Int { layers.count }
    }

    /// One single-color layer of a variant.
    struct Layer: Sendable, Hashable {
        let asset: String
        let role: Role
    }

    /// What a layer is painted with. `logo` is the VLC cone: Figma paints it with `Accent/Logo`,
    /// which equals `Accent/Main` in Dark but is darker in Light (#C2711A vs #E8851A).
    enum Role: Sendable, Hashable {
        case base, accent, accentDim, logo, placeholder, divider
    }

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    private let name: Name
    private let tone: Tone
    private let state: State
    private let size: CGFloat
    /// Style of the gray artwork; `nil` = whatever foreground style the environment provides.
    private let tint: AnyShapeStyle?

    /// - Parameters:
    ///   - name: the icon.
    ///   - tone: `.mono` (default) or `.twoTone` (menu icons).
    ///   - state: `.default`, `.active` or `.selected`.
    ///   - size: frame size in points; the artwork is drawn on a 24-unit grid scaled to it.
    ///   - tint: color of the gray artwork; `nil` leaves it unstyled so it takes the foreground style
    ///     set on the icon or an ancestor (`.foregroundStyle(_:)`).
    public init(_ name: Name, tone: Tone = .mono, state: State = .default, size: CGFloat = Theme.Metric.iconSize,
                tint: ThemeColor? = Theme.Color.fgA2) {
        self.init(name, tone: tone, state: state, size: size, anyTint: tint.map { AnyShapeStyle($0) })
    }

    /// An icon whose gray artwork is painted with any shape style (a gradient, a hierarchical style,
    /// a `Color` computed elsewhere). Accent and token-colored layers keep their roles.
    public init<Tint: ShapeStyle>(_ name: Name, tone: Tone = .mono, state: State = .default,
                                  size: CGFloat = Theme.Metric.iconSize, tint: Tint) {
        self.init(name, tone: tone, state: state, size: size, anyTint: AnyShapeStyle(tint))
    }

    private init(_ name: Name, tone: Tone, state: State, size: CGFloat, anyTint: AnyShapeStyle?) {
        self.name = name
        self.tone = tone
        self.state = state
        self.size = size
        self.tint = anyTint
    }

    public var body: some View {
        let resolved = Self.resolve(name, tone: tone, state: state)
        let scale = size / Theme.Metric.iconSize
        ZStack(alignment: .topLeading) {
            ForEach(Array(resolved.variant.layers.enumerated()), id: \.offset) { _, layer in
                Self.image(layer.asset)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: resolved.variant.canvas.width * scale, height: resolved.variant.canvas.height * scale)
                    .modifier(LayerStyle(style: style(for: layer.role, baseAsAccent: resolved.baseAsAccent)))
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
        .background {
            if differentiateWithoutColor && resolved.baseAsAccent {
                RoundedRectangle(cornerRadius: Theme.Radius.md * scale).fill(Theme.Color.iconHover)
            }
        }
        .accessibilityHidden(true)
    }

    /// The style of a layer; `nil` for untinted base artwork, which must not get a `foregroundStyle`
    /// of its own (`.foreground` there would resolve to the default label color, not the parent's style).
    private func style(for role: Role, baseAsAccent: Bool) -> AnyShapeStyle? {
        switch role {
        case .base:
            if baseAsAccent { return AnyShapeStyle(Theme.Color.accentMain) }
            return tint
        case .accent: return AnyShapeStyle(Theme.Color.accentMain)
        case .accentDim: return AnyShapeStyle(Theme.Color.accentDim)
        case .logo: return AnyShapeStyle(Theme.Color.accentLogo)
        case .placeholder: return AnyShapeStyle(Theme.Color.thumbPlaceholder)
        case .divider: return AnyShapeStyle(Theme.Color.dividerBright)
        }
    }

    /// Applies a layer's style, or nothing, so untinted layers inherit the environment's foreground style.
    private struct LayerStyle: ViewModifier {
        let style: AnyShapeStyle?

        func body(content: Content) -> some View {
            if let style {
                content.foregroundStyle(style)
            } else {
                content
            }
        }
    }

    private static func image(_ asset: String) -> Image {
        if let bundle = DesignSystem.resourceBundle {
            return Image(asset, bundle: bundle)
        }
        return Image(nsImage: NSImage())
    }

    // MARK: Lookup

    /// Whether Figma has exactly this variant (no fallback).
    public static func hasVariant(_ name: Name, tone: Tone = .mono, state: State = .default) -> Bool {
        variants(of: name).contains { $0.tone == tone && $0.state == state }
    }

    /// The variant drawn for a request, after fallbacks; `baseAsAccent` when a missing `.active`
    /// variant is replaced by the default artwork in the accent color.
    static func resolve(_ name: Name, tone: Tone, state: State) -> (variant: Variant, baseAsAccent: Bool) {
        let all = variants(of: name)
        func find(_ t: Tone, _ s: State) -> Variant? { all.first { $0.tone == t && $0.state == s } }
        if let exact = find(tone, state) { return (exact, false) }
        if tone == .twoTone, let mono = find(.mono, state) { return (mono, false) }
        if let plain = find(tone, .default) ?? find(.mono, .default) { return (plain, state == .active) }
        return (all[0], false)
    }

    // MARK: AppKit

    /// The icon as an `NSImage` with resolved colors, for AppKit (menus, toolbar items). Colors follow
    /// the appearance the image is drawn in; accent parts use `accent`. AppKit has no inherited
    /// foreground style, so a `nil` tint draws the gray artwork in `Theme.Color.fgA2`; use
    /// `templateImage(_:tone:state:size:)` when AppKit should tint the icon.
    public static func nsImage(_ name: Name, tone: Tone = .mono, state: State = .default,
                               size: CGFloat = Theme.Metric.iconSize, accent: Theme.Accent = .orange,
                               tint: ThemeColor? = Theme.Color.fgA2) -> NSImage {
        let resolved = resolve(name, tone: tone, state: state)
        let layers: [(NSImage, NSColor)] = resolved.variant.layers.compactMap { layer in
            guard let image = DesignSystem.resourceBundle?.image(forResource: layer.asset) else { return nil }
            let token: ThemeColor = switch layer.role {
            case .base: resolved.baseAsAccent ? Theme.Color.accentMain : (tint ?? Theme.Color.fgA2)
            case .accent: Theme.Color.accentMain
            case .accentDim: Theme.Color.accentDim
            case .logo: Theme.Color.accentLogo
            case .placeholder: Theme.Color.thumbPlaceholder
            case .divider: Theme.Color.dividerBright
            }
            return (image, token.nsColor(accent: accent))
        }
        let scale = size / Theme.Metric.iconSize
        let canvas = NSSize(width: resolved.variant.canvas.width * scale, height: resolved.variant.canvas.height * scale)
        let image = NSImage(size: canvas, flipped: true) { rect in
            for (layer, color) in layers {
                tinted(layer, color: color, size: rect.size).draw(in: rect)
            }
            return true
        }
        // Artwork that overflows the 24×24 frame (an accent dot) stays visible; layout uses the frame,
        // which sits at the top-left of the canvas.
        image.alignmentRect = NSRect(x: 0, y: canvas.height - size, width: size, height: size)
        image.accessibilityDescription = name.rawValue
        return image
    }

    /// The icon as a single-color template `NSImage` (all layers), for native menus that tint images.
    public static func templateImage(_ name: Name, tone: Tone = .mono, state: State = .default,
                                     size: CGFloat = Theme.Metric.iconSize) -> NSImage {
        let image = nsImage(name, tone: tone, state: state, size: size, tint: Theme.Color.fgA2)
        let template = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.black.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        template.alignmentRect = image.alignmentRect
        template.isTemplate = true
        template.accessibilityDescription = name.rawValue
        return template
    }

    private static func tinted(_ image: NSImage, color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
