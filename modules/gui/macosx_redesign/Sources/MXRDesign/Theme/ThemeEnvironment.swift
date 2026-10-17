import SwiftUI

private struct MXRAccentKey: EnvironmentKey {
    static let defaultValue: Theme.Accent = .orange
}

private struct MXRThemeModeKey: EnvironmentKey {
    static let defaultValue: Theme.Mode = .dark
}

extension EnvironmentValues {
    /// The accent that accent-dependent tokens (`Theme.Color.accentMain`, …) and icons resolve with.
    /// Set it with `.mxrAccent(_:)`. Default: `.orange`.
    public var mxrAccent: Theme.Accent {
        get { self[MXRAccentKey.self] }
        set { self[MXRAccentKey.self] = newValue }
    }

    /// The theme the user picked (`Theme.Mode`). Colors resolve from `colorScheme`, which
    /// `.mxrTheme(_:)` sets together with this value; this one tells views that need to show the
    /// setting itself (the onboarding theme tiles) whether `system` is selected.
    public var mxrThemeMode: Theme.Mode {
        get { self[MXRThemeModeKey.self] }
        set { self[MXRThemeModeKey.self] = newValue }
    }
}

extension View {
    /// Sets the accent for this view hierarchy: accent-dependent tokens, two-tone icons and the
    /// native control tint (`.tint`) follow it.
    public func mxrAccent(_ accent: Theme.Accent) -> some View {
        environment(\.mxrAccent, accent)
            .tint(Theme.Color.accentMain)
    }

    /// Applies a theme mode to this view hierarchy: `.dark` / `.light` force the color scheme,
    /// `.system` leaves the inherited one. For whole windows also set `NSWindow.appearance` to
    /// `mode.nsAppearance`, so AppKit chrome (menus, scroll bars) matches.
    public func mxrTheme(_ mode: Theme.Mode) -> some View {
        modifier(MXRThemeModifier(mode: mode))
    }
}

private struct MXRThemeModifier: ViewModifier {
    let mode: Theme.Mode
    @Environment(\.colorScheme) private var inherited

    func body(content: Content) -> some View {
        content
            .environment(\.mxrThemeMode, mode)
            .environment(\.colorScheme, mode.colorScheme ?? inherited)
    }
}
