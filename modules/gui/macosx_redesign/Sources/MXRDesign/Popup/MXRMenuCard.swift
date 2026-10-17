import Accelerate
import AppKit
import MXRCore
import SwiftUI

/// Highlight state of one menu card, shared by the pointer and the keyboard.
@MainActor
@Observable
final class MXRMenuTracking {
    /// The highlighted row (pointer or keyboard).
    var highlighted: Int? {
        didSet { if oldValue != highlighted { onHighlight?(highlighted) } }
    }
    /// Told when the highlight moves (VoiceOver follows it, PLAYER-07).
    @ObservationIgnored var onHighlight: ((Int?) -> Void)?
    /// The row whose submenu (or `⋯` actions) is open; it stays highlighted.
    var expanded: Int?
}

/// A design-system menu card (Figma `menu`, `context menu`, `right-click menu`, `Dropdown`
/// options): rows of two-tone icon, title, Mac-glyph shortcut or submenu chevron, orange check
/// for the current choice, BG/A2 hover row and Divider/Dim separators.
///
/// Popups present it through ``SwiftUI/View/mxrPopupMenu(isPresented:placement:style:width:items:)``
/// and ``SwiftUI/View/mxrContextMenu(style:width:items:)``. Gallery entries draw it directly with
/// a fixed highlight.
public struct MXRMenuCard: View {
    private let items: [MXRMenuItem]
    private let style: MXRPopupStyle
    private let width: CGFloat
    private let highlighted: Int?
    private let expanded: Int?
    private let activates: Bool

    /// - Parameters:
    ///   - highlighted: the hovered row, for gallery states.
    ///   - expanded: the row whose submenu is shown beside the card.
    ///   - activates: a click runs the row's action (a card drawn in place, e.g. in a gallery or
    ///     test). Presented popups handle clicks themselves.
    public init(items: [MXRMenuItem], style: MXRPopupStyle = .contextMenu, width: CGFloat? = nil,
                highlighted: Int? = nil, expanded: Int? = nil, activates: Bool = false) {
        self.activates = activates
        self.items = items
        self.style = style
        self.width = width ?? style.width
        self.highlighted = highlighted
        self.expanded = expanded
    }

    public var body: some View {
        MXRMenuCardContent(items: items, style: style, width: width, scrollHeight: nil,
                           highlighted: highlighted ?? expanded, expanded: expanded,
                           onHover: { _ in },
                           onActivate: { [items, activates] index in
                               guard activates, items.indices.contains(index), items[index].isEnabled,
                                     case .action(let action) = items[index].kind else { return }
                               action()
                           },
                           onAccessory: { _ in })
    }
}

/// The card's drawing, used by ``MXRMenuCard`` and by presented popups.
struct MXRMenuCardContent: View {
    let items: [MXRMenuItem]
    let style: MXRPopupStyle
    let width: CGFloat
    /// Height of the scrolling row area when the card does not fit on the screen.
    let scrollHeight: CGFloat?
    let highlighted: Int?
    let expanded: Int?
    let onHover: (Int?) -> Void
    let onActivate: (Int) -> Void
    let onAccessory: (Int) -> Void

    var body: some View {
        rows
            .padding(style.padding)
            .background { MXRPopupSurface(style: style) }
            .onHover { inside in if !inside { onHover(nil) } }
            .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var rows: some View {
        let stack = MXRMenuStackLayout(spacing: style.rowSpacing,
                                       minWidth: width - style.padding.horizontal,
                                       maxWidth: max(width, style.maxWidth) - style.padding.horizontal) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if item.isSeparator {
                    Rectangle().fill(Theme.Color.dividerDim).frame(height: Theme.Stroke.hairline)
                        .accessibilityHidden(true)
                } else {
                    MXRMenuRow(item: item, style: style, isHighlighted: highlighted == index,
                               onAccessory: item.actions == nil ? nil : { onAccessory(index) })
                        .id(index)
                        .onHover { inside in if inside { onHover(index) } }
                        .onTapGesture { onActivate(index) }
                        .accessibilityAction { onActivate(index) }
                }
            }
        }
        if let scrollHeight {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { stack }
                    .scrollIndicators(.automatic)
                    .frame(height: scrollHeight)
                    .onChange(of: highlighted) { _, row in
                        if let row { proxy.scrollTo(row) }
                    }
            }
        } else {
            stack
        }
    }
}

/// One Figma `option` row.
struct MXRMenuRow: View {
    let item: MXRMenuItem
    let style: MXRPopupStyle
    let isHighlighted: Bool
    let onAccessory: (() -> Void)?

    var body: some View {
        let row = style.row
        HStack(spacing: row.gap) {
            leading
            Text(item.title)
                .mxrTextStyle(Theme.Font.body)
                .foregroundStyle(item.isSecondary ? Theme.Color.fgA3 : Theme.Color.fgA2)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(row.padding)
        .frame(height: row.height)
        .background {
            if isHighlighted || item.isChecked {
                RoundedRectangle(cornerRadius: row.radius ?? Theme.Radius.md).fill(Theme.Color.bgA2)
            }
        }
        .opacity(item.isEnabled ? 1 : Theme.Popup.disabledOpacity)
        .contentShape(.rect)
        // A card drawn in place (gallery). Presented popups publish AXMenu/AXMenuItem from AppKit
        // instead (MXRMenuAccessibilityItem).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel ?? item.title)
        .accessibilityHint(item.isSubmenu ? "Opens submenu" : "")
        .accessibilityAddTraits(item.isChecked ? .isSelected : [])
    }

    /// The check moves to the icon slot when the row has no icon (Figma `Profiles`), and replaces
    /// the icon when the trailing slot holds a shortcut.
    private var checkLeads: Bool { item.icon == nil || item.shortcut != nil || item.isSubmenu }

    @ViewBuilder private var leading: some View {
        if let onAccessory {
            MXRIcon(.more)
                .contentShape(.rect)
                .onTapGesture(perform: onAccessory)
        } else if item.isChecked && checkLeads && (style.reservesIconSlot || item.icon != nil) {
            MXRIcon(.check, state: .active)
        } else if let icon = item.icon {
            MXRIcon(icon, tone: item.iconTone, state: item.iconState)
        } else if style.reservesIconSlot {
            Color.clear.frame(width: Theme.Metric.Menus.menuIcon, height: Theme.Metric.Menus.menuIcon)
        }
    }

    @ViewBuilder private var trailing: some View {
        if item.isSubmenu {
            MXRIcon(.chevronRight)
        } else if let shortcut = item.shortcut {
            Text(shortcut.displayString)
                .mxrTextStyle(Theme.Font.body)
                .foregroundStyle(Theme.Color.fgA3)
                .lineLimit(1)
                .fixedSize()
        } else if item.isChecked && !(checkLeads && (style.reservesIconSlot || item.icon != nil)) {
            MXRIcon(.check, state: .active)
        }
    }
}

/// Rows stacked at their natural heights, all as wide as the widest row (within `minWidth...maxWidth`),
/// so a card is as wide as Figma's frame and grows for long titles like an `NSMenu`.
struct MXRMenuStackLayout: Layout {
    let spacing: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = resolvedWidth(proposal: proposal, subviews: subviews)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        let total = heights.reduce(0, +) + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: width, height: total)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let height = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }

    private func resolvedWidth(proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite, width > 0 { return min(max(width, minWidth), maxWidth) }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return min(max(ideal, minWidth), maxWidth)
    }
}

// MARK: - Surface

private struct MXRPopupInWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True inside a popup's own window: its backdrop blurs what is behind the window.
    var mxrPopupInOwnWindow: Bool {
        get { self[MXRPopupInWindowKey.self] }
        set { self[MXRPopupInWindowKey.self] = newValue }
    }
}

/// Card fill, backdrop blur and the outside-only drop shadow of a popup style.
struct MXRPopupSurface: View {
    let style: MXRPopupStyle
    @Environment(\.mxrNativeBackdropEnabled) private var nativeBackdropEnabled
    @Environment(\.mxrPopupInOwnWindow) private var inOwnWindow

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.radius)
        ZStack {
            if style.blursBackdrop && nativeBackdropEnabled {
                MXRPopupBackdrop(behindWindow: inOwnWindow).clipShape(shape)
            }
            shape.fill(style.fill)
        }
        .background { if let shadow = style.shadow { OutsideShadow(shadow: shadow, radius: style.radius) } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A Figma drop shadow: the card shape grown by `spread`, offset and blurred, drawn only
    /// outside the translucent card (`showShadowBehindNode = false`).
    ///
    /// The shadow is rasterized once per card size into a bitmap (a Gaussian with Figma's σ, see
    /// ``MXRPopupShadowImage/sigmaPerBlur``), so the window server, `cacheDisplay` captures and
    /// `ImageRenderer` all show the same falloff (D-12: blur filters are dropped by some capture
    /// paths, which left menu shadows unverifiable).
    private struct OutsideShadow: View {
        let shadow: Theme.Shadow
        let radius: CGFloat
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            GeometryReader { proxy in
                let extent = MXRPopupShadowImage.extent(of: shadow)
                if let image = MXRPopupShadowImage.image(card: proxy.size, radius: radius, shadow: shadow,
                                                         scale: displayScale) {
                    Image(decorative: image, scale: displayScale)
                        .resizable()
                        .frame(width: proxy.size.width + extent * 2, height: proxy.size.height + extent * 2)
                        .offset(x: -extent, y: -extent)
                }
            }
        }
    }
}

/// Bitmaps of popup drop shadows, cached by card size.
@MainActor
enum MXRPopupShadowImage {
    private struct Key: Hashable {
        let width: CGFloat, height: CGFloat, radius: CGFloat, scale: CGFloat
        let shadow: Theme.Shadow
    }
    private static var cache: [Key: CGImage] = [:]

    /// Figma's drop-shadow kernel per point of the shadow's blur: a Gaussian of σ 0.45 × blur cut
    /// off at 0.93 × blur. Figma's raster falls off faster than the CSS σ = blur / 2 and ends
    /// sooner than any untruncated Gaussian; both were fitted on the 15 pt menu shadow of
    /// `Profiles` 6648:20666 (the right and bottom card edges agree within 0.5/255). Core
    /// Graphics' `setShadow` blur has no documented kernel (it drew σ 7 pt with a long tail), so
    /// the bitmap convolves the card shape itself.
    static let sigmaPerBlur: CGFloat = 0.45
    static let reachPerBlur: CGFloat = 0.93

    /// How far the shadow reaches past the card on each side (the kernel, the offset and the spread).
    static func extent(of shadow: Theme.Shadow) -> CGFloat {
        (shadow.blur * reachPerBlur + max(abs(shadow.x), abs(shadow.y)) + shadow.spread).rounded(.up)
    }

    /// The shadow around a `card`-sized rounded rectangle, `extent` larger on every side; clear
    /// inside the card (Figma `showShadowBehindNode = false`).
    static func image(card: CGSize, radius: CGFloat, shadow: Theme.Shadow, scale: CGFloat) -> CGImage? {
        guard card.width > 0, card.height > 0, scale > 0 else { return nil }
        let key = Key(width: card.width, height: card.height, radius: radius, scale: scale, shadow: shadow)
        if let image = cache[key] { return image }
        let extent = extent(of: shadow)
        let width = Int(((card.width + extent * 2) * scale).rounded(.up))
        let height = Int(((card.height + extent * 2) * scale).rounded(.up))
        // CG pixels, y up: the card sits `extent` in from every side, and Figma's downward y is -y.
        let cardRect = CGRect(x: extent * scale, y: extent * scale, width: card.width * scale, height: card.height * scale)
        let caster = cardRect.insetBy(dx: -shadow.spread * scale, dy: -shadow.spread * scale)
            .offsetBy(dx: shadow.x * scale, dy: -shadow.y * scale)

        // Coverage of the shadow-casting shape, 0…1 per pixel.
        guard let mask = CGContext(data: nil, width: width, height: height, bitsPerComponent: 32, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGImageAlphaInfo.none.rawValue | CGBitmapInfo.floatComponents.rawValue
                                       | CGBitmapInfo.byteOrder32Little.rawValue),
              let maskData = mask.data else { return nil }
        mask.addPath(Path(roundedRect: caster, cornerRadius: (radius + shadow.spread) * scale, style: .continuous).cgPath)
        mask.setFillColor(gray: 1, alpha: 1)
        mask.fillPath()
        var source = vImage_Buffer(data: maskData, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                   rowBytes: mask.bytesPerRow)
        var blurred = [Float](repeating: 0, count: width * height)
        let kernel = kernel(sigma: shadow.blur * sigmaPerBlur * scale, reach: shadow.blur * reachPerBlur * scale)
        let ok = blurred.withUnsafeMutableBytes { bytes -> Bool in
            var buffer = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.stride)
            // Separable: rows into `buffer`, then columns back into the mask.
            let flags = vImage_Flags(kvImageBackgroundColorFill)
            return vImageConvolve_PlanarF(&source, &buffer, nil, 0, 0, kernel, 1, UInt32(kernel.count), 0, flags) == kvImageNoError
                && vImageConvolve_PlanarF(&buffer, &source, nil, 0, 0, kernel, UInt32(kernel.count), 1, 0, flags) == kvImageNoError
        }
        guard ok else { return nil }

        guard let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outputData = output.data else { return nil }
        let color = shadow.color
        let coverage = maskData.assumingMemoryBound(to: Float.self)
        let pixels = outputData.assumingMemoryBound(to: UInt8.self)
        let maskStride = mask.bytesPerRow / MemoryLayout<Float>.stride
        for row in 0..<height {
            for column in 0..<width {
                let alpha = Double(min(max(coverage[row * maskStride + column], 0), 1)) * color.alpha
                let pixel = pixels + row * output.bytesPerRow + column * 4
                pixel[0] = UInt8((color.red * alpha * 255).rounded())
                pixel[1] = UInt8((color.green * alpha * 255).rounded())
                pixel[2] = UInt8((color.blue * alpha * 255).rounded())
                pixel[3] = UInt8((alpha * 255).rounded())
            }
        }
        output.addPath(Path(roundedRect: cardRect, cornerRadius: radius * scale, style: .continuous).cgPath)
        output.setBlendMode(.clear)
        output.fillPath()
        guard let image = output.makeImage() else { return nil }
        if cache.count > 64 { cache.removeAll() }
        cache[key] = image
        return image
    }

    /// A normalized Gaussian of `sigma` pixels cut off at `reach` pixels.
    private static func kernel(sigma: CGFloat, reach: CGFloat) -> [Float] {
        let half = max(1, Int(reach.rounded()))
        let weights = (-half...half).map { offset in Float(exp(-0.5 * pow(CGFloat(offset) / max(sigma, 0.01), 2))) }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total }
    }
}

/// Figma "bg blur" behind a popup card. In the popup's own window it blurs what lies behind the
/// window (the video); drawn inside another window (gallery) it blurs that window's content.
private struct MXRPopupBackdrop: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let behindWindow: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }

    private func configure(_ view: NSVisualEffectView) {
        view.blendingMode = behindWindow ? .behindWindow : .withinWindow
        view.state = .active
        view.material = .hudWindow
        view.isEmphasized = false
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
