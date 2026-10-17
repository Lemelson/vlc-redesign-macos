import SwiftUI

public extension View {
    /// Keyboard focus for custom chrome controls (seek bar, volume cone, sliders, EQ bands,
    /// Customize tiles), D028 / C1.
    ///
    /// - Focus comes only from keyboard navigation (Tab with "Keyboard navigation" on in System
    ///   Settings, like `NSSlider`); a click or drag never focuses the control.
    /// - The system focus ring (drawn in the user's accent colour, a square around the whole view
    ///   and its overlays) is disabled.
    /// - While keyboard-focused, the design's ring is drawn instead: `fgA1` (the primary foreground,
    ///   at least 3:1 on the chrome surfaces) following the control's corner radius. It sits outside
    ///   the control with a `Theme.Spacing.gap2` gap, so it is drawn on the bar surface and never over
    ///   the control's own fill (the accent play button, the seek fill).
    ///
    /// Key handlers (`onKeyPress`) attached after this modifier receive keys while focused.
    func mxrKeyboardFocusable(cornerRadius: CGFloat = Theme.Radius.lg) -> some View {
        modifier(MXRKeyboardFocusModifier(cornerRadius: cornerRadius))
    }
}

private struct MXRKeyboardFocusSuspendedKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True behind a modal dialog: custom chrome controls leave the keyboard focus order.
    var mxrKeyboardFocusSuspended: Bool {
        get { self[MXRKeyboardFocusSuspendedKey.self] }
        set { self[MXRKeyboardFocusSuspendedKey.self] = newValue }
    }
}

private struct MXRKeyboardFocusModifier: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var focused: Bool
    @Environment(\.mxrKeyboardFocusSuspended) private var suspended

    func body(content: Content) -> some View {
        content
            .focusable(!suspended, interactions: .activate)
            .focused($focused)
            .focusEffectDisabled()
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .inset(by: -MXRKeyboardFocusRing.outset)
                        .stroke(Theme.Color.fgA1, lineWidth: Theme.Stroke.iconActive)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// Geometry of the keyboard focus ring.
public enum MXRKeyboardFocusRing {
    /// Distance from the control's edge to the centre of the ring's stroke: a gap plus half the stroke.
    public static let outset = Theme.Spacing.gap2 + Theme.Stroke.iconActive / 2
}
