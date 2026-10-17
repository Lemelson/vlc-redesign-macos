import AppKit
import SwiftUI

private struct NativeBackdropEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// Live AppKit backdrops are enabled in the application by default.
    /// Disable only for isolated tint/geometry fixtures that have no native scene
    /// behind the surface. Such captures do not verify native blur appearance.
    var mxrNativeBackdropEnabled: Bool {
        get { self[NativeBackdropEnabledKey.self] }
        set { self[NativeBackdropEnabledKey.self] = newValue }
    }
}

private struct BarsBesidePictureKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// The window's bars are pinned beside the picture over the canvas base, not over the video
    /// (Player - Light, D055). Set by the window composition; read by the bars only, so popovers and
    /// tooltips drawn inside a bar keep their live material over the video.
    var mxrBarsBesidePicture: Bool {
        get { self[BarsBesidePictureKey.self] }
        set { self[BarsBesidePictureKey.self] = newValue }
    }
}

public extension View {
    /// Selects live material or tint-only rendering for this view's backdrop surfaces.
    func mxrNativeBackdropEnabled(_ enabled: Bool) -> some View {
        environment(\.mxrNativeBackdropEnabled, enabled)
    }
}

/// A live, within-window AppKit backdrop with a separately drawn Figma tint.
///
/// Use this as a background for surfaces marked `BG/* Transparent` in the design.
/// The tint resolves through the SwiftUI environment (scheme, accent, contrast).
/// AppKit controls the material's blur kernel; it does not expose Figma's fixed background-blur
/// radius. Figma composes the tint over the blurred content only, and this surface is meant for
/// chrome over dark content (the video, or a dialog scrim), so the material keeps a dark base in
/// both color schemes (D046): a light `aqua` base would replace that content under the light tint
/// and make light chrome far lighter than `Player - Light` (bars #ABABAA, panel #C2C2C1). Those
/// values are the tint over that frame's #2D2B29 video; over a bright video the surface takes on
/// some of the video's colour, as Figma's background blur does (D053).
/// A surface that is not over the video or a scrim (a native `.sheet`, a dialog body) must not use
/// it directly in Light: the dark base would turn it mid grey (#A7A7A7). Use the dialog surface
/// (`MXRDialogSurface` in MXRUI), which fills Light with the tint's `opaqueCounterpart`.
/// Native-window visual verification remains necessary. Keep this live view out of
/// `drawingGroup()` or other bitmap-only rendering paths.
///
/// With Reduce Transparency or Increase Contrast on, the material is dropped and the surface is
/// filled with the tint's opaque Figma style (`BG/A3 Transparent` → `BG/A3`).
public struct MXRBackdropSurface: View {
    @Environment(\.mxrNativeBackdropEnabled) private var nativeBackdropEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private let tint: ThemeColor
    private let cornerRadius: CGFloat
    private let material: NSVisualEffectView.Material
    private let overCanvasBase: Bool

    /// - Parameter overCanvasBase: the surface lies over the canvas base (``MXRBackdropBase``), not
    ///   over the video. Figma's background blur of that flat base is the base itself, so the surface
    ///   is exactly the tint over it, with no material: an `NSVisualEffectView` would add its own
    ///   material colour, which Figma's stack does not have (D053).
    public init(tint: ThemeColor, cornerRadius: CGFloat = 0,
                material: NSVisualEffectView.Material = .hudWindow, overCanvasBase: Bool = false) {
        self.tint = tint
        self.cornerRadius = max(0, cornerRadius)
        self.material = material
        self.overCanvasBase = overCanvasBase
    }

    public var body: some View {
        ZStack {
            if reduceTransparency || contrast == .increased {
                Rectangle().fill(tint.opaqueCounterpart)
            } else if overCanvasBase {
                Rectangle().fill(MXRBackdropBase())
                Rectangle().fill(tint)
            } else {
                if nativeBackdropEnabled {
                    WithinWindowBackdrop(material: material)
                }
                Rectangle().fill(tint)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The dark content a backdrop surface is drawn for (D046), for chrome that sits over no video.
///
/// `BG/* Transparent` chrome is the tint over the blurred video. Player - Light's bars are #D5D5D5
/// @ 0.75 over its video, which reads #2D2B29 under them (`Theme.Color.videoUnderBars`, the frame's
/// image fill), so they are #ABABAA. Where the bars are pinned beside the picture instead of over it
/// (the Light window, D055), the canvas under them is this base in both schemes, not the theme's
/// light `BG/B2` (#DEDEDE, which turned the bars #BB live), and the bars compose their tint over it
/// (``MXRBackdropSurface`` `overCanvasBase`), exactly Figma's layer stack.
public struct MXRBackdropBase: ShapeStyle {
    public init() {}

    public func resolve(in environment: EnvironmentValues) -> SwiftUI.Color {
        Theme.Color.videoUnderBars.resolve(in: environment)
    }
}

public extension ThemeColor {
    /// The opaque Figma style a `BG/* Transparent` style is the translucent form of
    /// (`BG/A3 Transparent` → `BG/A3`); the color itself when there is none.
    var opaqueCounterpart: ThemeColor {
        let suffix = " Transparent"
        guard let style = token.figmaStyle, style.hasSuffix(suffix),
              let opaque = Theme.ColorToken(figmaStyle: String(style.dropLast(suffix.count))) else { return self }
        return ThemeColor(opaque)
    }
}

private struct WithinWindowBackdrop: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NonVibrantEffectView {
        let view = NonVibrantEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NonVibrantEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NonVibrantEffectView) {
        view.blendingMode = .withinWindow
        view.state = .active
        view.material = material
        view.isEmphasized = false
        // Dark base in both schemes; the Figma tint drawn on top carries the theme.
        view.appearance = NSAppearance(named: .darkAqua)
    }
}

/// Text and the explicit tint live outside the effect's vibrancy hierarchy.
private final class NonVibrantEffectView: NSVisualEffectView {
    override var allowsVibrancy: Bool { false }
}
